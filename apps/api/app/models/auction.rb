class Auction < ApplicationRecord
  CURRENCY = "EUR"
  STATES = %w[draft scheduled active closed cancelled].freeze
  EDITABLE_FIELDS = %w[title description starting_price minimum_increment starts_at ends_at].freeze
  TRANSITIONS = {
    "scheduled" => %w[draft],
    "active" => %w[scheduled],
    "cancelled" => %w[draft scheduled active]
  }.freeze

  belongs_to :current_leader, class_name: "User", optional: true
  has_many :maximum_bids, autosave: false, validate: false, dependent: :restrict_with_exception, inverse_of: :auction

  belongs_to :winner, class_name: "User", optional: true, inverse_of: :won_auctions
  has_many :bids, dependent: :restrict_with_exception, inverse_of: :auction

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 10_000 }, exclusion: { in: [ nil ] }
  validates :status, inclusion: { in: STATES }
  validates :starting_price, :current_price, :minimum_increment, minor_units: true
  validates :starts_at, :ends_at, :original_ends_at, presence: true
  validate :valid_time_window
  validate :valid_price_and_winner
  validate :managed_changes

  def self.create_draft!(attributes)
    auction = new(attributes)
    auction.original_ends_at = auction.ends_at
    auction.current_price = auction.starting_price_before_type_cast
    auction.save!
    auction
  end

  def edit_draft!(attributes)
    transaction(requires_new: true) do
      reload(lock: true)
      unless status == "draft"
        raise DomainError.new("invalid_auction_state", "Only draft auctions can be edited.")
      end
      assign_attributes(attributes)
      self.original_ends_at = ends_at
      self.current_price = starting_price_before_type_cast
      persist_public_change!(:draft_edit)
      self
    end
  end

  def schedule!
    transition_to!("scheduled")
  end

  def activate!
    transition_to!("active")
  end

  # Finalize if due. Discovery and callers cannot force an early close.
  def close!
    close_lag = nil
    result = transaction(requires_new: true) do
      Observability.lock_wait("close") { reload(lock: true) }
      decision_time = AuctionClock.now
      return self if status == "closed"
      unless status == "active"
        raise DomainError.new("invalid_state_transition", "Only active auctions can close.")
      end
      return self unless AuctionDeadline.due?(ends_at, decision_time)

      close_lag = [ decision_time - ends_at, 0 ].max
      self.winner_id = current_leader_id
      self.closed_at = decision_time
      self.status = "closed"
      Observability.trace("hammerfall.auction.close") { persist_public_change!(:transition) }
      self
    end
    Observability.histogram("hammerfall_auction_close_lag", close_lag) if close_lag
    result
  end

  def cancel!
    transition_to!("cancelled")
  end

  # PostgreSQL owns serialization across all Rails processes.
  def place_bid!(bidder:, amount:)
    # Preserve atomicity even if a caller rescues failure inside an outer transaction.
    transaction(requires_new: true) do
      Observability.lock_wait("place_bid") { reload(lock: true) }
      Observability.trace("hammerfall.bid.decide", attributes: { "hammerfall.operation" => "place_bid" }) do
        decision_time = AuctionClock.now
        validate_bidding_window!(decision_time)

        bid = Bid.new(auction_id: id, bidder: bidder, amount: amount, sequence: (bids.maximum(:sequence) || 0) + 1)
        raise ActiveRecord::RecordInvalid.new(bid) unless bid.valid?(:placement)

        minimum = minimum_bid
        if bid.amount < minimum
          raise DomainError.new("bid_too_low", "Bid must be at least #{minimum} cents.", details: { minimum_bid: minimum, current_price: current_price })
        end

        accepted_bid = Observability.trace("hammerfall.proxy.resolve") do
          Bidding::ProxyResolver.new(self).manual(bidder, bid.amount)
        end
        persist_bidding_action!(decision_time)
        accepted_bid
      end
    end
  end

  def set_maximum!(bidder:, maximum_amount:)
    transaction(requires_new: true) do
      Observability.lock_wait("set_maximum_bid") { reload(lock: true) }
      Observability.trace("hammerfall.bid.decide", attributes: { "hammerfall.operation" => "set_maximum_bid" }) do
        decision_time = AuctionClock.now
        validate_bidding_window!(decision_time)
        instruction = MaximumBid.find_or_initialize_by(auction_id: id, bidder_id: bidder&.id)
        instruction.bidder = bidder
        previous = instruction.maximum_amount
        instruction.maximum_amount = maximum_amount
        instruction.priority_sequence ||= 1
        raise ActiveRecord::RecordInvalid.new(instruction) unless instruction.valid?(:maximum_configuration)

        if previous && maximum_amount < previous
          raise DomainError.new("maximum_bid_cannot_decrease", "Maximum bids cannot decrease.")
        end
        return instruction if previous == maximum_amount

        minimum = current_leader_id.nil? ? starting_price : current_price + (current_leader_id == bidder.id ? 0 : 1)
        if maximum_amount < minimum
          raise DomainError.new("maximum_bid_too_low", "Maximum does not cover the public price.", details: { current_price: current_price })
        end
        instruction.priority_sequence = (maximum_bids.maximum(:priority_sequence) || 0) + 1
        instruction.save!(context: :maximum_configuration)
        Observability.trace("hammerfall.proxy.resolve") { Bidding::ProxyResolver.new(self).maximum(instruction) }
        persist_bidding_action!(decision_time)
        instruction
      end
    end
  end

  def minimum_bid
    bids.exists? ? current_price + minimum_increment : starting_price
  end

  def leading_bid
    bids.where(bidder_id: current_leader_id).order(sequence: :desc).first
  end

  private

  def validate_bidding_window!(at)
    unless status == "active"
      raise DomainError.new("invalid_auction_state", "Bids require an active auction.", details: { status: status })
    end
    if AuctionDeadline.due?(ends_at, at)
      raise DomainError.new("auction_ended", "The auction has ended.", details: { ends_at: ends_at.utc.iso8601(6) })
    end
    unless starts_at <= at
      raise DomainError.new("auction_not_open", "The bidding window is not open.")
    end
  end

  def transition_to!(target)
    transaction(requires_new: true) do
      reload(lock: true)
      return self if status == target

      unless TRANSITIONS.fetch(target).include?(status)
        raise DomainError.new("invalid_state_transition", "Cannot transition from #{status} to #{target}.", details: { from: status, to: target })
      end
      check_transition_preconditions!(target, AuctionClock.now)
      self.status = target
      persist_public_change!(:transition)
      self
    end
  end

  def check_transition_preconditions!(target, at)
    case target
    when "scheduled"
      raise DomainError.new("invalid_state_transition", "Cannot schedule an auction whose end has passed.") if ends_at <= at
    when "active"
      unless starts_at <= at && at < ends_at
        raise DomainError.new("invalid_state_transition", "Activation requires an open bidding window.")
      end
    when "cancelled"
      raise DomainError.new("invalid_state_transition", "Cannot cancel an auction with accepted bids.") if bids.exists?
    end
  end

  # One accepted external commitment, independently of generated Bid count.
  def persist_bidding_action!(decision_time)
    self.ends_at = AuctionDeadline.extended_end(ends_at, decision_time)
    persist_public_change!(:bid_placement)
  end

  # Called once per logical command, while its auction lock/transaction is held.
  # Private-only maximum changes leave this row entirely unchanged (including time).
  def persist_public_change!(context)
    changed = (changes_to_save.keys & (EDITABLE_FIELDS + %w[current_price current_leader_id status winner_id original_ends_at closed_at])).any?
    self.public_revision += 1 if changed
    @persisting_public_change = true
    Observability.trace("hammerfall.postgresql.auction_save") { save!(context: context) }
    if changed
      event_type = if saved_change_to_status? && status == "closed"
        "auction.closed.v1"
      elsif saved_change_to_status?
        "auction.status_changed.v1"
      elsif context == :draft_edit
        "auction.terms_changed.v1"
      elsif saved_change_to_current_price? || saved_change_to_current_leader_id?
        "auction.price_changed.v1"
      else
        "auction.extended.v1"
      end
      public_data = { title: title, description: description, status: status,
        starting_price: starting_price, minimum_increment: minimum_increment,
        starts_at: starts_at.utc.iso8601(6), original_ends_at: original_ends_at.utc.iso8601(6),
        current_price: current_price, current_leader_id: current_leader_id,
        ends_at: ends_at.utc.iso8601(6), closed_at: closed_at&.utc&.iso8601(6), winner_id: winner_id }
      Observability.trace("hammerfall.outbox.persist", attributes: { "hammerfall.event_type" => event_type }) do
        OutboxEvent.record_auction_change!(auction_id: id, revision: public_revision,
          domain_event_type: event_type, domain_payload: public_data)
      end
    end
  ensure
    @persisting_public_change = false
  end

  def valid_time_window
    errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
    errors.add(:original_ends_at, "must be after starts_at") if starts_at && original_ends_at && original_ends_at <= starts_at
  end

  def valid_price_and_winner
    errors.add(:ends_at, "must not precede original_ends_at") if ends_at && original_ends_at && ends_at < original_ends_at
    if status == "closed"
      errors.add(:closed_at, "must be present") unless closed_at
      errors.add(:winner, "must match current leader") unless winner_id == current_leader_id
    elsif closed_at
      errors.add(:closed_at, "is only assigned on closure")
    end
    if current_price && starting_price && current_price < starting_price
      errors.add(:current_price, "must not be below starting_price")
    end
    errors.add(:winner, "is only assigned on closure") if winner_id && status != "closed"
    if new_record?
      errors.add(:current_leader, "must be empty initially") if current_leader_id
      errors.add(:status, "must start as draft") unless status == "draft"
      errors.add(:current_price, "must equal starting_price initially") unless current_price == starting_price
    end
  end

  # Validation guards only; lifecycle writes happen explicitly in the methods above.
  def managed_changes
    if new_record?
      errors.add(:public_revision, "must start at zero") unless public_revision == 0
      return
    end
    if will_save_change_to_public_revision? && !@persisting_public_change
      errors.add(:public_revision, "must be assigned by a public command")
    end
    if EDITABLE_FIELDS.any? { |field| will_save_change_to_attribute?(field) } && !@persisting_public_change
      errors.add(:base, "Auction terms must change through a public command")
    end

    if will_save_change_to_current_leader_id? && validation_context != :bid_placement
      errors.add(:current_leader, "must be changed through bidding")
    end
    if will_save_change_to_status? && validation_context != :transition
      errors.add(:status, "must be changed through a lifecycle action")
    end
    if will_save_change_to_winner_id? && validation_context != :transition
      errors.add(:winner, "must be assigned through closure")
    end
    if will_save_change_to_current_price? && ![ :draft_edit, :bid_placement ].include?(validation_context)
      errors.add(:current_price, "must be changed through draft editing or bid placement")
    end
    if will_save_change_to_ends_at? && ![ :draft_edit, :bid_placement ].include?(validation_context)
      errors.add(:ends_at, "must be changed through draft editing or soft close")
    end
    if will_save_change_to_closed_at? && validation_context != :transition
      errors.add(:closed_at, "must be assigned through closure")
    end
    if will_save_change_to_original_ends_at? && !(status_in_database == "draft" && validation_context == :draft_edit)
      errors.add(:original_ends_at, "must be changed through draft editing")
    end
    if EDITABLE_FIELDS.any? { |field| will_save_change_to_attribute?(field) && !(field == "ends_at" && validation_context == :bid_placement) }
      errors.add(:base, "Auction terms can only change while draft") unless status_in_database == "draft"
      if will_save_change_to_starting_price? && validation_context != :draft_edit
        errors.add(:starting_price, "must be changed through draft editing")
      end
    end
  end
end
