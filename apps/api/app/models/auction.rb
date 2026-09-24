class Auction < ApplicationRecord
  CURRENCY = "EUR"
  STATES = %w[draft scheduled active closed cancelled].freeze
  EDITABLE_FIELDS = %w[title description starting_price minimum_increment starts_at ends_at].freeze
  TRANSITIONS = {
    "scheduled" => %w[draft],
    "active" => %w[scheduled],
    "closed" => %w[active],
    "cancelled" => %w[draft scheduled active]
  }.freeze

  belongs_to :winner, class_name: "User", optional: true, inverse_of: :won_auctions
  has_many :bids, dependent: :restrict_with_exception, inverse_of: :auction

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 10_000 }, exclusion: { in: [ nil ] }
  validates :status, inclusion: { in: STATES }
  validates :starting_price, :current_price, :minimum_increment, minor_units: true
  validates :starts_at, :ends_at, presence: true
  validate :valid_time_window
  validate :valid_price_and_winner
  validate :managed_changes

  def self.create_draft!(attributes)
    auction = new(attributes)
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
      self.current_price = starting_price_before_type_cast
      save!(context: :draft_edit)
      self
    end
  end

  def schedule!(at: nil)
    transition_to!("scheduled", at: at)
  end

  def activate!(at: nil)
    transition_to!("active", at: at)
  end

  def close!(at: nil)
    transition_to!("closed", at: at)
  end

  def cancel!
    transition_to!("cancelled", at: nil)
  end

  # PostgreSQL owns serialization across all Rails processes.
  def place_bid!(bidder:, amount:, at: nil)
    # Preserve atomicity even if a caller rescues failure inside an outer transaction.
    transaction(requires_new: true) do
      reload(lock: true)
      at ||= Time.current
      unless status == "active"
        raise DomainError.new("invalid_auction_state", "Bids require an active auction.", details: { status: status })
      end
      unless starts_at <= at && at < ends_at
        raise DomainError.new("auction_not_open", "The bidding window is not open.")
      end

      bid = bids.build(bidder: bidder, amount: amount, sequence: (bids.maximum(:sequence) || 0) + 1)
      raise ActiveRecord::RecordInvalid.new(bid) unless bid.valid?(:placement)

      minimum = minimum_bid
      if bid.amount < minimum
        raise DomainError.new("bid_too_low", "Bid must be at least #{minimum} cents.", details: { minimum_bid: minimum, current_price: current_price })
      end

      bid.save!(context: :placement)
      self.current_price = bid.amount
      save!(context: :bid_placement)
      bid
    end
  end

  def minimum_bid
    bids.exists? ? current_price + minimum_increment : starting_price
  end

  def leading_bid
    bids.order(amount: :desc, id: :asc).first
  end

  private

  def transition_to!(target, at:)
    transaction(requires_new: true) do
      reload(lock: true)
      return self if status == target

      unless TRANSITIONS.fetch(target).include?(status)
        raise DomainError.new("invalid_state_transition", "Cannot transition from #{status} to #{target}.", details: { from: status, to: target })
      end
      check_transition_preconditions!(target, at || Time.current)
      self.winner = leading_bid&.bidder if target == "closed"
      self.status = target
      save!(context: :transition)
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
    when "closed"
      raise DomainError.new("invalid_state_transition", "Cannot close before ends_at.") if at < ends_at
    when "cancelled"
      raise DomainError.new("invalid_state_transition", "Cannot cancel an auction with accepted bids.") if bids.exists?
    end
  end

  def valid_time_window
    errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
  end

  def valid_price_and_winner
    if current_price && starting_price && current_price < starting_price
      errors.add(:current_price, "must not be below starting_price")
    end
    errors.add(:winner, "is only assigned on closure") if winner_id && status != "closed"
    if new_record?
      errors.add(:status, "must start as draft") unless status == "draft"
      errors.add(:current_price, "must equal starting_price initially") unless current_price == starting_price
    end
  end

  # Validation guards only; lifecycle writes happen explicitly in the methods above.
  def managed_changes
    return if new_record?

    if will_save_change_to_status? && validation_context != :transition
      errors.add(:status, "must be changed through a lifecycle action")
    end
    if will_save_change_to_winner_id? && validation_context != :transition
      errors.add(:winner, "must be assigned through closure")
    end
    if will_save_change_to_current_price? && ![ :draft_edit, :bid_placement ].include?(validation_context)
      errors.add(:current_price, "must be changed through draft editing or bid placement")
    end
    if EDITABLE_FIELDS.any? { |field| will_save_change_to_attribute?(field) }
      errors.add(:base, "Auction terms can only change while draft") unless status_in_database == "draft"
      if will_save_change_to_starting_price? && validation_context != :draft_edit
        errors.add(:starting_price, "must be changed through draft editing")
      end
    end
  end
end
