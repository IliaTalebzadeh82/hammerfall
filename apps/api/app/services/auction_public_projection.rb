require "digest"

# Disposable, public-only state. Redis is never consulted by an auction command.
class AuctionPublicProjection
  class InvalidProjection < StandardError; end

  KEY_PREFIX = "hammerfall:auction-public:v2:".freeze
  SCRIPT = <<~LUA.freeze
    local old = redis.call('GET', KEYS[1])
    local incoming = cjson.decode(ARGV[1])
    if old then
      local current = cjson.decode(old)
      if current.public_revision > incoming.public_revision then return 0 end
      if current.public_revision == incoming.public_revision then
        if current.data_digest == incoming.data_digest then return 2 end
        -- Earlier v2 entries predate closing_policy and were always regular.
        local legacy_regular = current.data.closing_policy == nil and
          incoming.data.closing_policy == 'regular' and current.data_digest == ARGV[2]
        if not legacy_regular then
          return redis.error_reply('projection revision conflict')
        end
      end
    end
    local now = redis.call('TIME')
    incoming.projected_at_ms = tonumber(now[1]) * 1000 + math.floor(tonumber(now[2]) / 1000)
    redis.call('SET', KEYS[1], cjson.encode(incoming))
    return 1
  LUA

  def initialize(redis: nil)
    @redis = redis || RedisClient.config(**RedisConnectionConfig.build, timeout: 1).new_client
  end

  def apply_event(event)
    write(auction_id: event.fetch("aggregate_id"), revision: event.fetch("aggregate_version"),
      event_id: event.fetch("event_id"), occurred_at: event.fetch("occurred_at"),
      source: "kafka", data: normalized_data(event))
  end

  def seed(auction)
    public_data = Api::V1::AuctionPresenter.new(auction).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
    write(auction_id: auction.id, revision: auction.public_revision, event_id: nil,
      occurred_at: auction.updated_at.iso8601(6), source: "postgresql_seed", data: public_data)
  end

  def read(auction_id)
    raw = @redis.call("GET", key(auction_id))
    return nil unless raw
    raise InvalidProjection, "projection too large" if raw.bytesize > 65_536
    state = JSON.parse(raw)
    raise InvalidProjection, "invalid projection envelope" unless state.is_a?(Hash) &&
      state.keys.sort == %w[auction_id data data_digest event_id occurred_at projected_at_ms public_revision schema_version source].sort &&
      state["schema_version"] == 2 && state["auction_id"] == auction_id &&
      state["public_revision"].is_a?(Integer) && state["public_revision"] >= 0 &&
      state["projected_at_ms"].is_a?(Integer) && state["projected_at_ms"].positive? &&
      %w[kafka postgresql_seed].include?(state["source"]) &&
      (state["source"] != "kafka" || (state["event_id"].is_a?(String) && state["public_revision"].positive?)) &&
      (state["source"] != "postgresql_seed" || state["event_id"].nil?)
    raise InvalidProjection, "invalid event identity" if state["event_id"] && !state["event_id"].match?(/\A[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    raise InvalidProjection, "invalid occurrence time" unless state["occurred_at"].is_a?(String) && Time.iso8601(state["occurred_at"])
    PublicAuctionSnapshot.validate!(state["data"])
    raise InvalidProjection, "projection digest mismatch" unless state["data_digest"] == digest(state["data"])
    unless state["data"].key?("closing_policy")
      state["data"]["closing_policy"] = "regular"
      state["data_digest"] = digest(state["data"])
    end
    state
  rescue JSON::ParserError, ArgumentError, PublicAuctionSnapshot::InvalidSnapshot
    raise InvalidProjection, "invalid projection state"
  end

  def close
    @redis.close
  end

  private

  def write(auction_id:, revision:, event_id:, occurred_at:, source:, data:)
    state = { schema_version: 2, auction_id: auction_id, public_revision: revision,
      event_id: event_id, occurred_at: occurred_at, source: source, data: data,
      data_digest: digest(data) }
    legacy_digest = data["closing_policy"] == "regular" ? digest(data.except("closing_policy")) : ""
    result = case @redis.call("EVAL", SCRIPT, 1, key(auction_id), JSON.generate(state), legacy_digest)
    when 1 then :applied
    when 2 then :duplicate
    else :stale
    end
    Observability.counter("hammerfall_projection_writes", attributes: { result: result })
    result
  rescue RedisClient::CommandError => error
    result = error.message.include?("projection revision conflict") ? "conflict" : "redis_failure"
    Observability.counter("hammerfall_projection_writes", attributes: { result: result })
    raise
  rescue RedisClient::Error
    Observability.counter("hammerfall_projection_writes", attributes: { result: "redis_failure" })
    raise
  end

  def digest(data)
    Digest::SHA256.hexdigest(JSON.generate(data.sort.to_h))
  end

  def normalized_data(event)
    data = event.fetch("data").dup
    # Historical v1 and earlier v2 events were all regular auctions.
    data["reserve_status"] = "none" if event.fetch("schema_version") == 1
    data["closing_policy"] ||= "regular"
    data
  end

  def key(auction_id)
    "#{KEY_PREFIX}#{auction_id}"
  end
end
