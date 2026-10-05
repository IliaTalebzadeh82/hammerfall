# Development-only Phase 21 proof through two real HTTP replicas and live Kafka/Redis.
require "./config/environment"
require "json"
require "securerandom"
require "./script/authenticated_smoke"

abort "development only" unless Rails.env.development?
a = ENV.fetch("API_REPLICA_A", "http://api:3000")
b = ENV.fetch("API_REPLICA_B", "http://api-replica-b:3000")
operator = AuthenticatedSmoke.new(base: a, login: "demo-operator")
alice = AuthenticatedSmoke.new(base: a, login: "demo-alice")
bob = AuthenticatedSmoke.new(base: b, login: "demo-bob")
now = AuctionClock.now
id = operator.expect(:post, "/api/v1/auctions", status: 201, base: a, body: { auction: {
  title: "Phase 21 policy smoke #{SecureRandom.hex(4)}", starting_price: 10_000,
  minimum_increment: 500, increment_policy: "stepped", reserve_price: 50_000,
  closing_policy: "rapid", starts_at: (now - 60).iso8601(6), ends_at: (now + 25).iso8601(6)
} }).dig("data", "id")
path = "/api/v1/auctions/#{id}"
operator.expect(:post, "#{path}/schedule", status: 200, base: a)
operator.expect(:post, "#{path}/activate", status: 200, base: b)
alice.expect(:put, "#{path}/maximum-bid", status: 200, base: a,
  body: { maximum_bid: { maximum_amount: 70_000 } }, key: SecureRandom.uuid)
auction = Auction.find(id)
raise "initial policy state incorrect" unless auction.closing_policy == "rapid" &&
  auction.reserve_status == "met" && auction.current_price == 50_000
original = auction.ends_at
while AuctionClock.now < original - 12
  sleep 0.1
end
key = SecureRandom.uuid
body = { maximum_bid: { maximum_amount: 60_000 } }
first = bob.request(:put, "#{path}/maximum-bid", body: body, key: key, base: a)
raise "rapid command failed: #{first[:status]}" unless first[:status] == 200 && first[:instance] == "a"
auction.reload
raise "combined policy state incorrect" unless auction.ends_at == original + 10 &&
  auction.current_price == 65_000 && auction.current_leader_id == alice.actor_id &&
  auction.reserve_status == "met" && auction.bids.maximum(:amount) <= 70_000
replay = bob.request(:put, "#{path}/maximum-bid", body: body, key: key, base: b)
raise "cross-replica replay changed deadline" unless replay[:status] == 200 && replay[:replayed] &&
  replay[:instance] == "b" && replay[:raw] == first[:raw] && Auction.find(id).ends_at == original + 10
public_state = bob.expect(:get, path, status: 200, base: b).fetch("data")
raise "replica B did not return authoritative policy" unless public_state.fetch("closing_policy") == "rapid" &&
  public_state.fetch("reserve_status") == "met" && public_state.fetch("ends_at") == auction.ends_at.iso8601(6)
# Wait for stable final state so a slow broker cannot race our active snapshot.
close_timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
until auction.reload.status == "closed"
  raise "autonomous closer timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= close_timeout
  sleep 0.1
end
raise "final reserve/closing outcome incorrect" unless auction.winner_id == alice.actor_id &&
  auction.current_leader_id == alice.actor_id && auction.ends_at == original + 10
expected = Api::V1::AuctionPresenter.new(auction).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 40
projection = AuctionPublicProjection.new
begin
  loop do
    rows = OutboxEvent.where(auction_id: id)
    state = projection.read(id)
    break if rows.count == auction.public_revision && rows.where.not(kafka_published_at: nil).count == rows.count &&
      ConsumedKafkaEvent.where(auction_id: id).count == rows.count && state && state.fetch("data") == expected
    raise "Kafka/Redis policy delivery timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.1
  end
  raise "private auction data leaked" if expected.key?("reserve_price") || expected.key?("maximum_amount") ||
    JSON.generate(projection.read(id)).match?(/reserve_price|maximum_amount|priority_sequence/)
  redis = RedisClient.config(**RedisConnectionConfig.build, timeout: 1).new_client
  begin
    redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{id}")
  ensure
    redis.close
  end
  raise "PostgreSQL rebuild failed" unless AuctionProjectionReconciler.new(projection: projection).check(auction.reload) == :repaired &&
    projection.read(id).fetch("data") == expected
ensure
  projection.close
end
puts JSON.generate(result: "PASS", auction_id: id, policy: "rapid", reserve_status: "met",
  visible_price: auction.current_price, deadline_extension_seconds: 10,
  final_status: auction.status, winner_id: auction.winner_id,
  auction_revision: auction.public_revision, replica_bid: first[:instance], replica_read: "b",
  replica_replay: replay[:instance], kafka_projection: "delivered", redis_rebuild: "matched")
