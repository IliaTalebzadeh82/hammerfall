# Local cross-process deadline/soft-close/closer races. Run via Rails runner
# from an API container with MODE=soft_close, deadline, or closer_race.
require "net/http"
require "json"
require "securerandom"

abort "development only" unless Rails.env.development?
mode = ENV.fetch("MODE")
raise "unknown mode" unless %w[soft_close deadline closer_race].include?(mode)
now = AuctionClock.now
deadline = now + (mode == "soft_close" ? 30 : 5)
users = 2.times.map { |i| User.create!(name: "P17 S2 #{mode} #{SecureRandom.hex(3)} #{i}") }
auction = Auction.create_draft!(title: "P17 S2 #{mode} #{SecureRandom.hex(4)}", description: "",
  starting_price: 10_000, minimum_increment: 1_000, starts_at: now - 60, ends_at: deadline)
auction.schedule!
auction.activate!
initial = { revision: auction.public_revision, ends_at: auction.ends_at.iso8601(6),
  original_ends_at: auction.original_ends_at.iso8601(6), outbox_count: OutboxEvent.where(auction_id: auction.id).count }
path = "/api/v1/auctions/#{auction.id}/bids"
bid = lambda do |instance, user, amount|
  uri = URI("http://#{instance == 'a' ? 'api' : 'api-replica-b'}:3000#{path}")
  message = Net::HTTP::Post.new(uri)
  message["Content-Type"] = "application/json"
  message["Idempotency-Key"] = SecureRandom.uuid
  message.body = JSON.generate(bid: { bidder_id: user.id, amount: amount })
  response = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 35) { |client| client.request(message) }
  { status: response.code.to_i, instance: response["X-Hammerfall-Instance"], body: JSON.parse(response.body) }
end
started = Queue.new
results = []
threads = []
blocker_count = lambda do |pid|
  connection = ApplicationRecord.connection
  connection.uncached do
    connection.execute("SELECT pg_stat_clear_snapshot()")
    connection.select_value("SELECT count(*) FROM pg_stat_activity AS waiting WHERE waiting.wait_event_type = 'Lock' AND (" \
      "#{Integer(pid)} = ANY(pg_blocking_pids(waiting.pid)) OR EXISTS (" \
      "SELECT 1 FROM pg_stat_activity AS first WHERE #{Integer(pid)} = ANY(pg_blocking_pids(first.pid)) " \
      "AND first.pid = ANY(pg_blocking_pids(waiting.pid))))")
  end.to_i
end
wait_blockers = lambda do |pid, count|
  limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
  until blocker_count.call(pid) >= count
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
      activity = ApplicationRecord.connection.exec_query("SELECT pid, pg_blocking_pids(pid) AS blockers, state, wait_event_type, wait_event, left(query, 120) AS query FROM pg_stat_activity WHERE backend_type = 'client backend' ORDER BY pid").to_a
      raise "#{mode}: #{count} row-lock waiters did not appear; threads=#{threads.map(&:status)} activity=#{activity}"
    end
    sleep 0.02
  end
end

ApplicationRecord.transaction do
  auction.reload(lock: true)
  holder = ApplicationRecord.connection.select_value("SELECT pg_backend_pid()").to_i
  threads << Thread.new { started << true; bid.call("a", users[0], 10_000) }
  started.pop
  wait_blockers.call(holder, 1)
  if mode != "closer_race"
    threads << Thread.new { started << true; bid.call("b", users[1], 11_000) }
    started.pop
    wait_blockers.call(holder, 2)
  end
  if mode == "deadline" || mode == "closer_race"
    raise "command did not wait before deadline" unless AuctionClock.now < auction.ends_at
    limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until AuctionClock.now >= auction.ends_at
      raise "deadline not reached" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
      sleep 0.02
    end
    wait_blockers.call(holder, 2) if mode == "closer_race"
  end
  client_backends = ApplicationRecord.connection.uncached do
    ApplicationRecord.connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend'").to_i
  end
  puts JSON.generate(scenario: mode, stage: "held", auction_id: auction.id, holder_pid: holder,
    blocked_connections: blocker_count.call(holder), db_time: AuctionClock.now.iso8601(6),
    deadline: auction.ends_at.iso8601(6), client_backends: client_backends)
end
results = threads.map(&:value)
auction.reload
limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
if mode == "closer_race"
  until auction.reload.status == "closed"
    raise "closer did not finalize" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limit
    sleep 0.05
  end
end
sql = { status: auction.status, price: auction.current_price, leader: auction.current_leader_id,
  revision: auction.public_revision, ends_at: auction.ends_at.iso8601(6),
  original_ends_at: auction.original_ends_at.iso8601(6), closed_at: auction.closed_at&.iso8601(6),
  winner: auction.winner_id, bids: auction.bids.order(:sequence).pluck(:id, :sequence, :amount, :bidder_id),
  maximum_count: auction.maximum_bids.count, outbox_count: OutboxEvent.where(auction_id: auction.id).count,
  completed_commands: IdempotencyRecord.where(actor_id: users.map(&:id), operation: "place_bid").count }
raise "wrong replica labels" unless results.map { |r| r[:instance] } == (mode == "closer_race" ? %w[a] : %w[a b])
if mode == "soft_close"
  raise "unexpected bid result" unless results.map { |r| r[:status] } == [ 201, 201 ]
  raise "soft-close SQL mismatch" unless sql[:bids].map { |r| r[1..2] } == [ [ 1, 10_000 ], [ 2, 11_000 ] ] &&
    sql[:price] == 11_000 && sql[:leader] == users[1].id && sql[:revision] == initial[:revision] + 2 &&
    auction.ends_at == deadline + 90 && auction.original_ends_at == deadline && sql[:outbox_count] == initial[:outbox_count] + 2
elsif mode == "deadline"
  raise "deadline rejection mismatch" unless results.map { |r| r[:status] } == [ 422, 422 ] &&
    results.all? { |r| r[:body].dig("error", "code") == "auction_ended" } && sql[:bids].empty? &&
    sql[:revision] == initial[:revision] && sql[:outbox_count] == initial[:outbox_count] && sql[:completed_commands] == 2
else
  raise "closer race mismatch" unless results[0][:status] == 422 &&
    %w[auction_ended invalid_auction_state].include?(results[0][:body].dig("error", "code")) &&
    sql[:status] == "closed" && sql[:bids].empty? && sql[:winner].nil? &&
    auction.closed_at >= auction.ends_at && sql[:revision] == initial[:revision] + 1 &&
    sql[:outbox_count] == initial[:outbox_count] + 1
end
post_close = nil
if mode == "closer_race"
  post_close = bid.call("b", users[1], 10_000)
  auction.reload
  raise "post-close mutation accepted" unless post_close[:instance] == "b" && post_close[:status] == 422 &&
    post_close[:body].dig("error", "code") == "invalid_auction_state" && auction.bids.empty? &&
    auction.public_revision == sql[:revision] && OutboxEvent.where(auction_id: auction.id).count == sql[:outbox_count]
  sql[:completed_commands] = IdempotencyRecord.where(actor_id: users.map(&:id), operation: "place_bid").count
  raise "post-close outcome absent" unless sql[:completed_commands] == 2
end
puts JSON.generate(scenario: mode, stage: "verified", auction_id: auction.id,
  initial: initial, results: results, post_close: post_close, sql: sql)
