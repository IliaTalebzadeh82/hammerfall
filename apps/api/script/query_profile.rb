#!/usr/bin/env ruby
# Isolated in-process Rack requests against real PostgreSQL. This profiles SQL
# shape without logging bind values, private maximums, command keys or raw SQL.
require "json"
require "rack/mock"
require "securerandom"

label = "phase15-query-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(3)}"
alice, bob, charlie = 3.times.map { |i| User.create!(name: "#{label}-user-#{i}") }
auction = Auction.create_draft!(title: label, description: "Phase 15 query fixture",
  starting_price: 10_000, minimum_increment: 500,
  starts_at: AuctionClock.now - 60, ends_at: AuctionClock.now + 3600)
auction.schedule!
auction.activate!
request = Rack::MockRequest.new(Rails.application)
$stdout = File.open(File::NULL, "w") # Discard routine per-request logs in this isolated profiler process.
bid_path = "/api/v1/auctions/#{auction.id}/bids"
maximum_path = "/api/v1/auctions/#{auction.id}/maximum-bid"

def profile_request(request, label, method, path, body, key, expected_status)
  queries = []
  subscriber = lambda do |_name, start_time, finish_time, _id, payload|
    next if payload[:cached]

    sql = payload[:sql].to_s
    table = sql[/\b(?:FROM|INTO|UPDATE|JOIN)\s+"?([a-z_]+)"?/i, 1]
    table = "other" unless %w[auctions bids maximum_bids idempotency_records outbox_events users].include?(table)
    kind = if sql.match?(/\bFOR UPDATE\b/i)
      "row_lock"
    elsif sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK)/i)
      "transaction"
    else
      sql[/\A\s*([A-Z]+)/i, 1]&.upcase || "other"
    end
    queries << { kind: kind, table: table, name: payload[:name].to_s,
      milliseconds: (finish_time - start_time) * 1000 }
  end
  response = nil
  elapsed = nil
  ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = request.request(method, path, "CONTENT_TYPE" => "application/json",
      "HTTP_HOST" => "api", "HTTP_IDEMPOTENCY_KEY" => key, input: JSON.generate(body))
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  end
  raise "unexpected status for #{label}: #{response.status}" unless response.status == expected_status

  grouped = queries.group_by { |query| [ query[:kind], query[:table] ] }
  { scenario: label, status: response.status, replayed: response["Idempotency-Replayed"] == "true",
    rack_ms: elapsed.round(3), query_count: queries.length,
    sql_ms: queries.sum { |query| query[:milliseconds] }.round(3),
    groups: grouped.map { |(kind, table), rows| { kind: kind, table: table,
      count: rows.length, total_ms: rows.sum { |row| row[:milliseconds] }.round(3),
      max_ms: rows.map { |row| row[:milliseconds] }.max.round(3) } }.sort_by { |row| -row[:total_ms] } }
end

results = []
key = SecureRandom.uuid
bid = ->(user, amount) { { bid: { bidder_id: user.id, amount: amount } } }
maximum = ->(user, amount) { { maximum_bid: { bidder_id: user.id, maximum_amount: amount } } }
results << profile_request(request, "accepted_manual", "POST", bid_path, bid.call(alice, 10_000), key, 201)
results << profile_request(request, "accepted_manual_warm", "POST", bid_path, bid.call(bob, 10_500), SecureRandom.uuid, 201)
results << profile_request(request, "rejected_stale", "POST", bid_path, bid.call(bob, 10_000), SecureRandom.uuid, 422)
results << profile_request(request, "maximum_bid", "PUT", maximum_path, maximum.call(bob, 30_000), SecureRandom.uuid, 200)
results << profile_request(request, "competing_maximum", "PUT", maximum_path, maximum.call(alice, 50_000), SecureRandom.uuid, 200)
results << profile_request(request, "proxy_contested_manual", "POST", bid_path, bid.call(charlie, 31_000), SecureRandom.uuid, 201)
results << profile_request(request, "completed_replay", "POST", bid_path, bid.call(alice, 10_000), key, 201)

STDOUT.write(JSON.pretty_generate(fixture: { label: label, auction_id: auction.id }, results: results) + "\n")
