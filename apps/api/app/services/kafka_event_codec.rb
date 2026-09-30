class KafkaEventCodec
  class InvalidEvent < StandardError; end

  TYPES = %w[auction.closed.v1 auction.status_changed.v1 auction.terms_changed.v1 auction.price_changed.v1 auction.extended.v1].freeze
  ENVELOPE_KEYS = %w[event_id event_type schema_version aggregate_id aggregate_version occurred_at data].freeze
  DATA_KEYS = PublicAuctionSnapshot::DATA_KEYS

  def self.decode(payload, key:)
    raise InvalidEvent, "payload missing or too large" unless payload.is_a?(String) && payload.bytesize.between?(1, 65_536)
    event = JSON.parse(payload)
    raise InvalidEvent, "invalid envelope" unless event.is_a?(Hash) && event.keys.sort == ENVELOPE_KEYS.sort
    raise InvalidEvent, "unsupported schema or event type" unless event["schema_version"] == 1 && TYPES.include?(event["event_type"])
    raise InvalidEvent, "invalid identity" unless event["event_id"].is_a?(String) && event["event_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    raise InvalidEvent, "invalid aggregate" unless event["aggregate_id"].is_a?(Integer) && event["aggregate_id"].positive? &&
      event["aggregate_version"].is_a?(Integer) && event["aggregate_version"].positive? && key == event["aggregate_id"].to_s
    raise InvalidEvent, "invalid occurrence time" unless event["occurred_at"].is_a?(String) && Time.iso8601(event["occurred_at"])
    PublicAuctionSnapshot.validate!(event["data"])
    event
  rescue PublicAuctionSnapshot::InvalidSnapshot
    raise InvalidEvent, "invalid public data"
  rescue JSON::ParserError, ArgumentError
    raise InvalidEvent, "malformed JSON or time"
  end
end
