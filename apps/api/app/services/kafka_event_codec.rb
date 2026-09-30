class KafkaEventCodec
  class InvalidEvent < StandardError; end

  TYPES = %w[auction.closed.v1 auction.status_changed.v1 auction.terms_changed.v1 auction.price_changed.v1 auction.extended.v1].freeze
  ENVELOPE_KEYS = %w[event_id event_type schema_version aggregate_id aggregate_version occurred_at data].freeze
  DATA_KEYS = %w[title description status starting_price minimum_increment starts_at original_ends_at current_price current_leader_id ends_at closed_at winner_id].freeze

  def self.decode(payload, key:)
    raise InvalidEvent, "payload missing or too large" unless payload.is_a?(String) && payload.bytesize.between?(1, 65_536)
    event = JSON.parse(payload)
    raise InvalidEvent, "invalid envelope" unless event.is_a?(Hash) && event.keys.sort == ENVELOPE_KEYS.sort
    raise InvalidEvent, "unsupported schema or event type" unless event["schema_version"] == 1 && TYPES.include?(event["event_type"])
    raise InvalidEvent, "invalid identity" unless event["event_id"].is_a?(String) && event["event_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    raise InvalidEvent, "invalid aggregate" unless event["aggregate_id"].is_a?(Integer) && event["aggregate_id"].positive? &&
      event["aggregate_version"].is_a?(Integer) && event["aggregate_version"].positive? && key == event["aggregate_id"].to_s
    raise InvalidEvent, "invalid occurrence time" unless event["occurred_at"].is_a?(String) && Time.iso8601(event["occurred_at"])
    data = event["data"]
    raise InvalidEvent, "invalid public data" unless data.is_a?(Hash) && data.keys.sort == DATA_KEYS.sort &&
      data["title"].is_a?(String) && data["title"].length.between?(1, 200) &&
      data["description"].is_a?(String) && data["description"].length <= 10_000 &&
      Auction::STATES.include?(data["status"]) &&
      [ "starting_price", "minimum_increment", "current_price" ].all? { |field| data[field].is_a?(Integer) && data[field].positive? } &&
      [ "current_leader_id", "winner_id" ].all? { |field| data[field].nil? || (data[field].is_a?(Integer) && data[field].positive?) } &&
      [ "starts_at", "original_ends_at", "ends_at" ].all? { |field| data[field].is_a?(String) } &&
      (data["closed_at"].nil? || data["closed_at"].is_a?(String))
    Time.iso8601(data["starts_at"])
    Time.iso8601(data["original_ends_at"])
    Time.iso8601(data["ends_at"])
    Time.iso8601(data["closed_at"]) if data["closed_at"]
    event
  rescue JSON::ParserError, ArgumentError
    raise InvalidEvent, "malformed JSON or time"
  end
end
