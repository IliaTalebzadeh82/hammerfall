class User < ApplicationRecord
  has_secure_password validations: false
  has_many :user_sessions, dependent: :delete_all
  has_many :seller_auctions, class_name: "Auction", foreign_key: :seller_id, inverse_of: :seller, dependent: :restrict_with_exception
  has_many :maximum_bids, foreign_key: :bidder_id, inverse_of: :bidder, dependent: :restrict_with_exception
  has_many :bids, foreign_key: :bidder_id, inverse_of: :bidder, dependent: :restrict_with_exception
  has_many :won_auctions, class_name: "Auction", foreign_key: :winner_id, inverse_of: :winner, dependent: :restrict_with_exception

  validates :name, presence: true, length: { maximum: 100 }
  validates :login, format: { with: /\A[a-z0-9][a-z0-9._-]{2,63}\z/ }, allow_nil: true
  validates :login, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :role, inclusion: { in: %w[member operator] }
  validate :credential_pair
  validate :password_length, if: -> { password.present? }

  def operator?
    role == "operator"
  end

  private

  def credential_pair
    errors.add(:login, "and password must be provisioned together") if login.present? != password_digest.present?
  end

  def password_length
    errors.add(:password, "must be 12 to 72 bytes") unless (12..72).cover?(password.bytesize)
  end
end
