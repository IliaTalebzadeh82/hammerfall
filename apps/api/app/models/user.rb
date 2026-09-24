class User < ApplicationRecord
  has_many :maximum_bids, foreign_key: :bidder_id, inverse_of: :bidder, dependent: :restrict_with_exception
  has_many :bids, foreign_key: :bidder_id, inverse_of: :bidder, dependent: :restrict_with_exception
  has_many :won_auctions, class_name: "Auction", foreign_key: :winner_id, inverse_of: :winner, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 100 }
end
