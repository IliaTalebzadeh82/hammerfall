require "digest"
require "json"

module Idempotency
  class Executor
    Outcome = Data.define(:status, :body, :replayed)
    class InvalidKey < StandardError
      attr_reader :code
      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    def self.validate_key!(key)
      raise InvalidKey.new("idempotency_key_required", "Idempotency-Key is required for this operation.") if key.nil?
      unless key.is_a?(String) && key.ascii_only? && key.match?(/\A[!-~]{1,255}\z/)
        raise InvalidKey.new("invalid_idempotency_key", "Idempotency-Key must contain 1 to 255 visible ASCII characters without spaces.")
      end
      key
    end

    def self.call(key:, actor_id:, operation:, auction_id:, arguments:)
      validate_key!(key)
      raise ArgumentError, "Unknown idempotency operation" unless IdempotencyRecord::OPERATIONS.include?(operation)
      days = Integer(ENV.fetch("IDEMPOTENCY_RETENTION_DAYS", "7"))
      raise ArgumentError, "retention days must be between 1 and 365" unless (1..365).cover?(days)
      expiry = Arel.sql(IdempotencyRecord.sanitize_sql_array([ "CURRENT_TIMESTAMP + (? * INTERVAL '1 day')", days ]))
      scope = { actor_id: actor_id, operation: operation, key_digest: Digest::SHA256.hexdigest(key) }
      canonical = JSON.generate(api_version: "v1", operation: operation, auction_id: auction_id,
        actor_id: actor_id, arguments: arguments.sort.to_h)
      fingerprint = Digest::SHA256.hexdigest(canonical)

      IdempotencyRecord.transaction(requires_new: true) do
        loop do
          inserted = IdempotencyRecord.insert_all([ scope.merge(request_fingerprint: fingerprint,
            expires_at: expiry) ],
            unique_by: :index_idempotency_records_on_scope, returning: %w[id], record_timestamps: false)
          record = IdempotencyRecord.find_by(scope)
          # A prune can delete an expired conflict between INSERT and SELECT.
          # Physical removal permits reuse; try claiming again in that case only.
          next unless record
          if inserted.empty?
            if record.request_fingerprint != fingerprint
              break Outcome.new(status: 409, body: { "error" => { "code" => "idempotency_key_conflict",
                "message" => "This idempotency key was already used with a different request.", "details" => {} } }, replayed: false)
            end
            raise "Unexpected committed processing idempotency record" unless record.status == "completed"
            break Outcome.new(status: record.response_status, body: record.response_body, replayed: true)
          end

          # Auction commands use requires_new savepoints. Expected rejection rolls
          # their work back before this outer transaction stores the terminal error.
          status, body = begin
            yield
          rescue DomainError => error
            [ 422, { error: { code: error.code, message: error.message, details: error.details } } ]
          rescue ActiveRecord::RecordInvalid => error
            [ 422, { error: { code: "validation_failed", message: "Validation failed.", details: error.record.errors.to_hash } } ]
          rescue ActiveRecord::RecordNotFound => error
            code = { "Auction" => "auction_not_found", "User" => "user_not_found" }.fetch(error.model, "resource_not_found")
            [ 404, { error: { code: code, message: "Requested resource was not found.", details: {} } } ]
          end
          ChaosCrash.at_command!("command_before_commit", auction_id)
          record.update!(status: "completed", response_status: status, response_body: body)
          # Use the same JSONB-normalized snapshot for original and replay responses.
          record.reload
          break Outcome.new(status: record.response_status, body: record.response_body, replayed: false)
        end
      end
    end
  end
end
