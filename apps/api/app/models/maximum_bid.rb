class MaximumBid < ApplicationRecord
  belongs_to :auction, inverse_of: :maximum_bids
  belongs_to :bidder, class_name: "User", inverse_of: :maximum_bids

  validates :maximum_amount, minor_units: true
  validates :priority_sequence, numericality: { only_integer: true, greater_than: 0 }
  validate :configuration_entry_point

  def destroy
    raise ActiveRecord::ReadOnlyRecord, "Maximum bids cannot be cancelled"
  end

  private

  def configuration_entry_point
    errors.add(:base, "Use Auction#set_maximum! to configure protection") unless validation_context == :maximum_configuration
    errors.add(:bidder, "must be persisted") unless bidder&.persisted?
  end
end
