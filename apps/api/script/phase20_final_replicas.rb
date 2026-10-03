# Development-only real HTTP proof against two independent Rails replicas.
require "json"
require "net/http"
require "securerandom"
require "./script/authenticated_smoke"

abort "development only" unless Rails.env.development?
a = ENV.fetch("API_REPLICA_A", "http://api:3000")
b = ENV.fetch("API_REPLICA_B", "http://api-replica-b:3000")
operator = AuthenticatedSmoke.new(base: a, login: "demo-operator")
alice = AuthenticatedSmoke.new(base: a, login: "demo-alice")
bob = AuthenticatedSmoke.new(base: b, login: "demo-bob")
raise "B did not authenticate A's cookie" unless alice.expect(:get, "/api/v1/session", status: 200, base: b).dig("data", "id") == alice.actor_id

create = lambda do |label|
  now = AuctionClock.now
  id = operator.expect(:post, "/api/v1/auctions", status: 201, base: a, body: { auction: {
    title: "Phase 20 replicas #{label} #{SecureRandom.hex(4)}", starting_price: 10_000,
    minimum_increment: 1_000, starts_at: (now - 60).iso8601(6), ends_at: (now + 3600).iso8601(6)
  } }).dig("data", "id")
  path = "/api/v1/auctions/#{id}"
  operator.expect(:post, "#{path}/schedule", status: 200, base: a)
  operator.expect(:post, "#{path}/activate", status: 200, base: b)
  [ id, path ]
end

id, path = create.call("replay")
key = SecureRandom.uuid
body = { bid: { amount: 10_000 } }
first = alice.request(:post, "#{path}/bids", body: body, key: key, base: a)
replay = alice.request(:post, "#{path}/bids", body: body, key: key, base: b)
raise "cross-replica replay failed" unless first[:status] == 201 && replay[:status] == 201 &&
  replay[:replayed] && first[:raw] == replay[:raw] && first[:instance] == "a" && replay[:instance] == "b"
raise "duplicate SQL command" unless Auction.find(id).bids.count == 1

race_id, race_path = create.call("concurrent")
barrier = Queue.new
start = Queue.new
results = [ [ alice, a, 10_000 ], [ bob, b, 11_000 ] ].map do |client, base, amount|
  Thread.new do
    barrier << true
    start.pop
    client.request(:post, "#{race_path}/bids", body: { bid: { amount: amount } }, key: SecureRandom.uuid, base: base)
  end
end
2.times { barrier.pop }
2.times { start << true }
outcomes = results.map(&:value)
raise "unexpected competing-bid responses" unless outcomes.all? { |row| [ 201, 422 ].include?(row[:status]) }
race = Auction.find(race_id)
history = race.bids.order(:sequence).pluck(:sequence, :amount)
raise "PostgreSQL did not serialize competing bids" unless history.map(&:first) == (1..history.length).to_a &&
  race.current_price == 11_000 && race.public_revision == 2 + history.length && history.length == outcomes.count { |row| row[:status] == 201 }

alice.expect(:delete, "/api/v1/session", status: 204, base: b)
raise "A accepted B's revoked session" unless alice.request(:get, "/api/v1/session", base: a)[:status] == 401
raise "revoked actor could bid" unless alice.request(:post, "#{path}/bids", body: { bid: { amount: 20_000 } },
  key: SecureRandom.uuid, base: a)[:status] == 401

puts JSON.generate(result: "PASS", auth: "A->B->revoke B->reject A", replay_auction: id,
  replay_bid: first.dig(:body, "data", "id"), race_auction: race_id,
  race_instances: outcomes.map { |row| row[:instance] }, race_statuses: outcomes.map { |row| row[:status] },
  race_history: history)
