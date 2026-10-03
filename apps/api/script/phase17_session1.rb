# Run with bin/rails runner script/phase17_session1.rb in the api container.
# Each HTTP request uses a fresh connection to the normal Compose proxy.
require "json"
require "securerandom"
require "./script/authenticated_smoke"

abort "development only" unless Rails.env.development?
base = ENV.fetch("API_BASE_URL", "http://api-proxy:3000")
run_id = SecureRandom.hex(4)
operator = AuthenticatedSmoke.new(base: base, login: "demo-operator")
clients = %w[demo-alice demo-bob demo-carol].map { |login| AuthenticatedSmoke.new(base: base, login: login) }
users = clients.map(&:actor_id)
clients_by_id = clients.to_h { |client| [ client.actor_id, client ] }

request = lambda do |method, path, payload = nil, key = nil, client = operator|
  result = client.request(method, path, body: payload, key: key, base: base)
  if result[:status] == 429
    sleep(Integer(result.fetch(:retry_after)))
    result = client.request(method, path, body: payload, key: key, base: base)
  end
  result
end

ok = lambda do |method, path, payload = nil, key = nil, client = operator|
  result = request.call(method, path, payload, key, client)
  raise "#{method} #{path}: HTTP #{result[:status]} #{result[:body]}" unless [ 200, 201 ].include?(result[:status])
  raise "missing instance label" unless %w[a b].include?(result[:instance])
  result
end

create = lambda do |label|
  now = AuctionClock.now
  result = ok.call(:post, "/api/v1/auctions", { auction: {
    title: "P17 #{run_id} #{label}", starting_price: 10_000, minimum_increment: 500,
    starts_at: (now - 60).iso8601(6), ends_at: (now + 3600).iso8601(6)
  } })
  id = result[:body].fetch("data").fetch("id")
  path = "/api/v1/auctions/#{id}"
  schedule = ok.call(:post, "#{path}/schedule")
  activate = ok.call(:post, "#{path}/activate")
  [ id, path, [ result, schedule, activate ] ]
end

bid = lambda do |path, user, amount, key = SecureRandom.uuid|
  ok.call(:post, "#{path}/bids", { bid: { amount: amount } }, key, clients_by_id.fetch(user))
end
maximum = lambda do |path, user, amount, key = SecureRandom.uuid|
  ok.call(:put, "#{path}/maximum-bid", { maximum_bid: { maximum_amount: amount } }, key, clients_by_id.fetch(user))
end

verify = lambda do |id, expected_price, expected_leader, expected_amounts, expected_revision|
  auction = Auction.find(id)
  rows = auction.bids.order(:sequence).pluck(:sequence, :amount, :bidder_id)
  raise "SQL price/leader/revision mismatch" unless auction.current_price == expected_price &&
    auction.current_leader_id == expected_leader && auction.public_revision == expected_revision
  raise "SQL sequence mismatch" unless rows.map(&:first) == (1..rows.length).to_a
  raise "SQL history mismatch" unless rows.map { |row| row[1] } == expected_amounts
  raise "SQL winner should be absent" unless auction.winner_id.nil?
  { auction_id: id, price: auction.current_price, leader: auction.current_leader_id,
    revision: auction.public_revision, history: rows }
end

# Sequential HTTP commands switch between logical replicas while using one URL.
id, path, setup = create.call("sequential")
first = bid.call(path, users[0], 10_000)
second = bid.call(path, users[1], 11_000)
ceiling = maximum.call(path, users[0], 20_000)
get = ok.call(:get, path)
handling = (setup + [ first, second, ceiling, get ]).map { |row| row[:instance] }
raise "sequential commands did not cross replicas" unless handling.uniq.sort == %w[a b] && handling.each_cons(2).any? { |a, b| a != b }
sql = verify.call(id, 11_500, users[0], [ 10_000, 11_000, 11_500 ], 5)
raise "REST disagrees with SQL" unless get[:body].fetch("data").values_at("current_price", "current_leader_id", "public_revision") ==
  [ sql[:price], sql[:leader], sql[:revision] ]
puts JSON.generate(scenario: "sequential", instances: handling, sql: sql)

# Concurrent requests on one hot auction must serialize in PostgreSQL.
id, path, = create.call("concurrent")
barrier = Queue.new
start = Queue.new
threads = 10.times.map do |i|
  Thread.new do
    barrier << true
    start.pop
    request.call(:post, "#{path}/bids", { bid: { amount: 10_000 + i * 500 } }, SecureRandom.uuid, clients[i % clients.length])
  end
end
10.times { barrier.pop }
10.times { start << true }
results = threads.map(&:value)
raise "concurrent bids stayed on one replica" unless results.map { |row| row[:instance] }.uniq.sort == %w[a b]
accepted = results.select { |row| row[:status] == 201 }
rejected = results.select { |row| row[:status] == 422 && row[:body].dig("error", "code") == "bid_too_low" }
raise "unexpected concurrent outcome" unless accepted.length + rejected.length == results.length
auction = Auction.find(id)
rows = auction.bids.order(:sequence).pluck(:id, :sequence, :amount, :bidder_id)
raise "lost/extra bid" unless rows.map(&:first).sort == accepted.map { |row| row[:body].dig("data", "id") }.sort
raise "bad SQL sequence" unless rows.map { |row| row[1] } == (1..rows.length).to_a
raise "bad SQL price/leader/revision" unless auction.current_price == 14_500 &&
  auction.current_leader_id == users[9 % users.length] && auction.public_revision == 2 + accepted.length
puts JSON.generate(scenario: "concurrent", instances: results.map { |row| row[:instance] },
  accepted: accepted.length, rejected: rejected.length, auction_id: id,
  sql: { price: auction.current_price, leader: auction.current_leader_id, revision: auction.public_revision, history: rows })

# Equal private ceilings preserve the first durable priority across replicas.
id, path, = create.call("proxy-tie")
max_a = maximum.call(path, users[0], 30_000)
max_b = maximum.call(path, users[1], 30_000)
raise "maximum commands did not cross replicas" unless max_a[:instance] != max_b[:instance]
sql = verify.call(id, 30_000, users[0], [ 10_000, 30_000, 30_000 ], 4)
priorities = MaximumBid.where(auction_id: id).order(:priority_sequence).pluck(:bidder_id, :priority_sequence)
raise "priority mismatch" unless priorities == [ [ users[0], 1 ], [ users[1], 2 ] ]
public_body = ok.call(:get, path)[:body].to_json
raise "private metadata leaked" if public_body.match?(/"(?:maximum_amount|priority_sequence|origin)"\s*:|"automatic"/)
puts JSON.generate(scenario: "proxy-tie", instances: [ max_a[:instance], max_b[:instance] ], sql: sql,
  private_priority_order: priorities.map(&:last), public_private_leak: false)

# Same-key requests race on different processes; the committed outcome replays.
id, path, = create.call("idempotency")
key = SecureRandom.uuid
previous_records = IdempotencyRecord.uncached do
  IdempotencyRecord.where(actor_id: users[0], operation: "place_bid").count
end
barrier = Queue.new
start = Queue.new
threads = 2.times.map do
  Thread.new do
    barrier << true
    start.pop
    request.call(:post, "#{path}/bids", { bid: { amount: 10_000 } }, key, clients.first)
  end
end
2.times { barrier.pop }
2.times { start << true }
results = threads.map(&:value)
raise "same-key race stayed on one replica" unless results.map { |row| row[:instance] }.uniq.sort == %w[a b]
raise "same-key responses differ" unless results.map { |row| row[:body] }.uniq.length == 1 &&
  results.map { |row| row[:status] } == [ 201, 201 ] && results.count { |row| row[:replayed] } == 1
replay = nil
4.times do
  replay = request.call(:post, "#{path}/bids", { bid: { amount: 10_000 } }, key, clients.first)
  break if replay[:instance] != results.find { |row| !row[:replayed] }[:instance]
end
raise "completed replay failed" unless replay[:replayed] && replay[:body] == results.first[:body] &&
  replay[:instance] != results.find { |row| !row[:replayed] }[:instance]
sql = verify.call(id, 10_000, users[0], [ 10_000 ], 3)
current_records = IdempotencyRecord.uncached do
  IdempotencyRecord.where(actor_id: users[0], operation: "place_bid").count
end
raise "idempotency effect count #{previous_records} -> #{current_records}" unless current_records == previous_records + 1
puts JSON.generate(scenario: "idempotency", instances: results.map { |row| row[:instance] },
  replay_instance: replay[:instance], auction_id: id, sql: sql, effect_count: 1)

puts JSON.generate(result: "PASS", run_id: run_id)
