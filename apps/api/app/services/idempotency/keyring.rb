require "digest"
require "json"
require "openssl"

module Idempotency
  class Keyring
    LOCAL_KEY_ID = "local-v1"
    LOCAL_KEY = Digest::SHA256.hexdigest("hammerfall-local-development-test-only-idempotency-v1")
    KEY_ID = /\A[a-z0-9][a-z0-9_-]{0,31}\z/

    attr_reader :current_id, :keys

    def self.current
      @current ||= load!
    end

    def self.load!(env: ENV)
      path = env["IDEMPOTENCY_HMAC_KEYRING_FILE"]
      if path.nil? && !Rails.env.production?
        return new(current_id: LOCAL_KEY_ID, keys: { LOCAL_KEY_ID => LOCAL_KEY })
      end
      raise ArgumentError, "IDEMPOTENCY_HMAC_KEYRING_FILE must name a readable file" unless path && File.file?(path) && File.readable?(path)
      config = JSON.parse(File.read(path))
      raise ArgumentError, "Invalid idempotency HMAC keyring shape" unless config.is_a?(Hash) && config.keys.sort == %w[current keys]
      new(current_id: config.fetch("current"), keys: config.fetch("keys"))
    rescue JSON::ParserError
      raise ArgumentError, "IDEMPOTENCY_HMAC_KEYRING_FILE must contain JSON"
    end

    def initialize(current_id:, keys:)
      unless current_id.is_a?(String) && current_id.match?(KEY_ID) && keys.is_a?(Hash) && keys.any? &&
          keys.keys.all? { |id| id.is_a?(String) && id.match?(KEY_ID) } && keys.key?(current_id) &&
          keys.values.all? { |value| value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/) && value.chars.uniq.length > 8 } &&
          keys.values.uniq.length == keys.length
        raise ArgumentError, "Invalid idempotency HMAC keyring metadata or key quality"
      end
      @current_id = current_id
      @keys = keys.freeze
    end

    def digest(key, key_id)
      OpenSSL::HMAC.hexdigest("SHA256", [ keys.fetch(key_id) ].pack("H*"), key)
    end

    def lookup_scopes(actor_id:, operation:, key:)
      [ current_id, *(keys.keys - [ current_id ]) ].map do |key_id|
        { actor_id: actor_id, operation: operation, key_digest: digest(key, key_id) }
      end
    end

    def validate_retained_keys!
      missing = IdempotencyRecord.where(digest_version: 2).where.not(digest_key_id: keys.keys).exists?
      raise ArgumentError, "Idempotency keyring omits retained key IDs" if missing
    end
  end
end
