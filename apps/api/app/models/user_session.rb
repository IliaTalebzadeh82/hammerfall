require "digest"
require "openssl"
require "securerandom"

class UserSession < ApplicationRecord
  COOKIE_NAME = :hammerfall_session
  LIFETIME = 12.hours

  belongs_to :user

  def self.issue!(user)
    token = SecureRandom.hex(32)
    db_now = connection.select_value("SELECT clock_timestamp()")
    create!(user: user, token_digest: Digest::SHA256.hexdigest(token),
      created_at: db_now, updated_at: db_now, expires_at: db_now + LIFETIME)
    token
  end

  def self.resolve(token)
    return nil unless token.is_a?(String) && token.match?(/\A[0-9a-f]{64}\z/)
    includes(:user).where("expires_at > clock_timestamp()").find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def self.csrf_token(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "hammerfall-csrf-v1:#{token}")
  end

  def self.valid_csrf?(token, candidate)
    candidate.is_a?(String) && candidate.match?(/\A[0-9a-f]{64}\z/) &&
      ActiveSupport::SecurityUtils.secure_compare(csrf_token(token), candidate)
  end

  def self.prune_expired!(limit: 1_000)
    ids = where("expires_at <= clock_timestamp()").order(:expires_at, :id).limit(limit).pluck(:id)
    where(id: ids).delete_all
  end
end
