# Development-only, retained-fixture engineering showcase. All auction commands
# below use HTTP; direct model reads are explicitly labelled internal checks.
require "./config/environment"
require "./script/authenticated_smoke"
require "securerandom"
require "time"

abort "Showcase requires the development Compose stack" unless Rails.env.development?

def check!(condition, message)
  raise "Showcase failed: #{message}" unless condition
end

def amount(cents)
  format("€%d.%02d", cents / 100, cents % 100)
end

def public_state(client, path, base:)
  response = client.expect(:get, path, status: 200, base: base).fetch("data")
  check!((response.keys & %w[reserve_price maximum_amount priority_sequence origin]).empty?, "private field in public response")
  response
end

def wait_until(seconds, failure)
  limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  loop do
    value = yield
    return value if value
    raise "Showcase failed: #{failure}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
    sleep 0.1
  end
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
a = "http://api:3000"
b = "http://api-replica-b:3000"
puts "Hammerfall engineering showcase\n===============================\n"

begin
  [ a, b ].each do |base|
    response = Net::HTTP.get_response(URI("#{base}/up"))
    check!(response.code == "200", "API unhealthy at #{base}")
  end
  check!(ApplicationRecord.connection.select_value("SELECT 1") == 1, "PostgreSQL unhealthy")
  redis = RedisClient.config(**RedisConnectionConfig.build, timeout: 1).new_client
  begin
    check!(redis.call("PING") == "PONG", "Redis unhealthy")
  ensure
    redis.close
  end
  check!(User.where(login: %w[demo-operator demo-alice demo-bob]).count == 3,
    "demo identities missing; run docker compose exec -T api bin/rails db:seed")
  operator = AuthenticatedSmoke.new(base: a, login: "demo-operator")
  alice = AuthenticatedSmoke.new(base: a, login: "demo-alice")
  bob = AuthenticatedSmoke.new(base: b, login: "demo-bob")
rescue StandardError => error
  abort "Showcase prerequisites failed: #{error.message}"
end

# FIXTURE PREPARATION: a unique, labelled auction avoids modifying unrelated
# local data. It is retained for inspection and each run creates a fresh one.
now = AuctionClock.now
title = "Hammerfall engineering showcase #{now.utc.strftime('%Y%m%dT%H%M%S')} #{SecureRandom.hex(3)}"
data = operator.expect(:post, "/api/v1/auctions", status: 201, base: a, body: { auction: {
  title: title, starting_price: 10_000, minimum_increment: 500,
  increment_policy: "stepped", reserve_price: 50_000, closing_policy: "rapid",
  starts_at: (now - 60).iso8601(6), ends_at: (now + 90).iso8601(6)
} }).fetch("data")
id = data.fetch("id")
path = "/api/v1/auctions/#{id}"
operator.expect(:post, "#{path}/schedule", status: 200, base: a)
operator.expect(:post, "#{path}/activate", status: 200, base: b)
initial = public_state(alice, path, base: a)
check!(initial.values_at("status", "current_price", "reserve_status", "closing_policy") ==
  [ "active", 10_000, "not_met", "rapid" ], "initial public state")
check!(initial.fetch("minimum_increment") == 500, "initial stepped increment")
puts "[1/6] Fixture prepared (auction #{id}; isolated retained row)"
puts "      Public view: active, #{amount(initial.fetch('current_price'))}; reserve not met; opening bid #{amount(initial.fetch('starting_price'))}; rapid closing"
puts "      Public deadline #{Time.iso8601(initial.fetch('ends_at')).utc.iso8601(3)}; revision #{initial.fetch('public_revision')}"

# BEHAVIOR UNDER DEMONSTRATION: authenticated commands through real Rails HTTP.
alice.expect(:put, "#{path}/maximum-bid", status: 200, base: a,
  body: { maximum_bid: { maximum_amount: 70_000 } }, key: SecureRandom.uuid)
after_alice = public_state(alice, path, base: a)
check!(after_alice.values_at("current_price", "current_leader_id", "reserve_status") ==
  [ 50_000, alice.actor_id, "met" ], "Alice/reserve outcome")
puts "[2/6] Alice authorized a private ceiling"
puts "      Public view: #{amount(after_alice.fetch('current_price'))}; reserve met; private ceiling absent from response"

original_deadline = Time.iso8601(after_alice.fetch("ends_at"))
wait_until(90, "late bidding window missed") do
  remaining = original_deadline - AuctionClock.now
  check!(remaining > 3, "late bidding window missed")
  remaining <= 12
end
key = SecureRandom.uuid
body = { maximum_bid: { maximum_amount: 60_000 } }
first = bob.request(:put, "#{path}/maximum-bid", body: body, key: key, base: a)
check!(first[:status] == 200, "Bob command HTTP #{first[:status]}")
internal = Auction.find(id)
after_bob = public_state(bob, path, base: b)
check!(after_bob.values_at("current_price", "current_leader_id", "reserve_status") ==
  [ 65_000, alice.actor_id, "met" ], "proxy/stepped outcome")
check!(internal.ends_at == original_deadline + 10, "rapid extension must be exactly +10 seconds")
check!(internal.bids.count == 3, "proxy contest must create three visible bid rows")
puts "[3/6] Bob challenged through HTTP; proxy resolution stayed with Alice"
puts "      Public view: leader Alice, price #{amount(after_bob.fetch('current_price'))}"
puts "      Authoritative internal check: #{internal.bids.count} committed visible bid rows"
puts "[4/6] Late command extended the authoritative deadline"
puts "      Authoritative internal check: #{original_deadline.utc.iso8601(3)} → #{internal.ends_at.utc.iso8601(3)} (+10 seconds)"

before = ApplicationRecord.uncached do
  [ internal.bids.count, OutboxEvent.where(auction_id: id).count, internal.public_revision ]
end
replay = bob.request(:put, "#{path}/maximum-bid", body: body, key: key, base: b)
internal.reload
after = ApplicationRecord.uncached do
  [ internal.bids.count, OutboxEvent.where(auction_id: id).count, internal.public_revision ]
end
check!(replay[:status] == 200 && replay[:replayed] && replay[:raw] == first[:raw], "same-key historical replay")
check!(before == after, "replay created a bid/outbox/revision")
puts "[5/6] Bob retried the same command on the other replica"
puts "      Historical response replayed: yes; new mutation: no"

wait_until(45, "autonomous closer did not close the auction") { internal.reload.status == "closed" }
check!(internal.winner_id == alice.actor_id && internal.current_leader_id == alice.actor_id &&
  internal.current_price == 65_000 && internal.reserve_status == "met", "final PostgreSQL outcome")
closed = public_state(alice, path, base: a)
check!(closed.values_at("status", "winner_id", "public_revision") ==
  [ "closed", alice.actor_id, internal.public_revision ], "closed public GET differs from authority")
expected = Api::V1::AuctionPresenter.new(internal).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
projection = AuctionPublicProjection.new
begin
  checks = nil
  state = wait_until(45, "Kafka receipt/Redis projection did not converge") do
    # A Rails runner has a query cache; these rows change in other processes.
    ApplicationRecord.uncached do
      rows = OutboxEvent.where(auction_id: id)
      projected = projection.read(id)
      checks = { revision: internal.public_revision, outbox: rows.count,
        published: rows.where.not(kafka_published_at: nil).count,
        receipts: ConsumedKafkaEvent.where(auction_id: id).count,
        redis_revision: projected&.fetch("public_revision"), data_matches: projected && projected.fetch("data") == expected }
      checks[:outbox] == checks[:revision] && checks[:published] == checks[:outbox] &&
        checks[:receipts] == checks[:outbox] && checks[:redis_revision] == checks[:revision] &&
        checks[:data_matches] && projected
    end
  end
  check!((state.fetch("data").keys & %w[reserve_price maximum_amount priority_sequence origin]).empty?,
    "private field in Redis projection")
rescue RuntimeError => error
  raise "#{error.message}; observed #{checks.inspect}"
ensure
  projection.close
end
puts "[6/6] Public and derived state converged"
puts "      PostgreSQL authority revision #{internal.public_revision}; Redis derived revision #{state.fetch('public_revision')}; Kafka audit receipts #{checks.fetch(:receipts)}"
puts "      PostgreSQL committed the outcome before Kafka/Redis caught up."
puts "      Winner Alice; final public price #{amount(closed.fetch('current_price'))}; closed."
puts "\nPASS (#{format('%.1f', Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)}s)"
