class Bid < ApplicationRecord
  belongs_to :auction, inverse_of: :bids
  belongs_to :bidder, class_name: "User", inverse_of: :bids

  validates :amount, minor_units: true
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }
  validate :persisted_participants
  validate :placement_entry_point, on: :create

  # Accepted bids are historical facts. Corrections are not supported.
  def readonly?
    persisted? || super
  end

  private

  def persisted_participants
    errors.add(:auction, "must be persisted") unless auction&.persisted?
    errors.add(:bidder, "must be persisted") unless bidder&.persisted?
  end

  def placement_entry_point
    errors.add(:base, "Use Auction#place_bid! to accept a bid") unless validation_context == :placement
  end
end
