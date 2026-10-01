# Run inside the API container via `bin/rails runner script/benchmark_verify.rb`.
# BENCHMARK_MANIFEST contains the JSON emitted by load-tests/prepare.py.
require "json"
require "digest"

manifest = JSON.parse(ENV.fetch("BENCHMARK_MANIFEST"))
ids = manifest.fetch("auctions").map { |id| Integer(id) }
raise "empty auction fixture" if ids.empty?

failures = []
summaries = ids.map do |id|
  auction = Auction.find(id)
  bids = Bid.where(auction_id: id).order(:sequence).pluck(:sequence, :amount, :bidder_id, :origin)
  sequences = bids.map(&:first)
  failures << "auction #{id}: non-contiguous or duplicated bid sequence" unless sequences == (1..bids.length).to_a
  if bids.empty?
    failures << "auction #{id}: unexpected price/leader without bids" unless
      auction.current_price == auction.starting_price && auction.current_leader_id.nil?
  else
    last = bids.last
    failures << "auction #{id}: price/leader disagree with final bid" unless
      auction.current_price == last[1] && auction.current_leader_id == last[2]
  end
  failures << "auction #{id}: winner disagrees with leader" if
    auction.status == "closed" && auction.winner_id != auction.current_leader_id
  failures << "auction #{id}: winner outside closed state" if auction.status != "closed" && auction.winner_id
  maxima = MaximumBid.where(auction_id: id).pluck(:bidder_id, :maximum_amount, :priority_sequence)
  limits = maxima.to_h { |bidder_id, amount, _priority| [ bidder_id, amount ] }
  bids.each do |sequence, amount, bidder_id, origin|
    failures << "auction #{id}: automatic bid #{sequence} exceeded ceiling" if
      origin == "automatic" && amount > limits.fetch(bidder_id, -1)
  end
  priorities = maxima.map(&:last)
  failures << "auction #{id}: duplicate maximum priority" if priorities.uniq.length != priorities.length
  revisions = OutboxEvent.where(auction_id: id).order(:public_revision).pluck(:public_revision)
  failures << "auction #{id}: outbox/public revision mismatch" unless
    revisions == (1..auction.public_revision).to_a
  closing_detail = nil
  if %w[closing challenge].include?(manifest.fetch("scenario"))
    events = OutboxEvent.where(auction_id: id).order(:public_revision).pluck(
      :public_revision, :domain_event_type, :domain_payload, :occurred_at)
    previous_end = auction.original_ends_at
    extensions = []
    observed_before_deadline = 0
    timing_inconclusive = 0
    events.each do |revision, type, payload, occurred_at|
      snapshot_end = Time.iso8601(payload.fetch("ends_at"))
      delta = (snapshot_end - previous_end).round(6)
      failures << "auction #{id}: invalid deadline delta at revision #{revision}" unless [ 0, 90 ].include?(delta)
      if %w[auction.price_changed.v1 auction.extended.v1].include?(type)
        # Outbox occurred_at is a PostgreSQL timestamp sampled after the bid
        # decision. If it still precedes the prior deadline, that bid was on
        # time. A later event timestamp is inconclusive, not proof of lateness.
        if occurred_at < previous_end
          observed_before_deadline += 1
        else
          timing_inconclusive += 1
        end
      end
      if delta == 90
        failures << "auction #{id}: extension without bid at revision #{revision}" unless type == "auction.price_changed.v1" || type == "auction.extended.v1"
        extensions << { revision: revision, observed_at: occurred_at.utc.iso8601(6), ends_at: snapshot_end.utc.iso8601(6) }
      end
      previous_end = snapshot_end
    end
    failures << "auction #{id}: final deadline disagrees with event history" unless previous_end == auction.ends_at
    failures << "auction #{id}: expected a soft-close extension" if extensions.empty?
    failures << "auction #{id}: closer did not finalize auction" unless auction.status == "closed"
    failures << "auction #{id}: missing final close event" unless events.last&.at(1) == "auction.closed.v1"
    failures << "auction #{id}: closure before effective deadline" unless auction.closed_at && auction.closed_at >= auction.ends_at
    failures << "auction #{id}: unexpected command/revision count" unless
      auction.public_revision == 3 + bids.count { |row| row[3] == "manual" }
    closing_detail = { original_ends_at: auction.original_ends_at.utc.iso8601(6),
      extensions: extensions, closed_at: auction.closed_at&.utc&.iso8601(6),
      close_lag_seconds: auction.closed_at && (auction.closed_at - auction.ends_at).round(6),
      event_observed_before_prior_deadline: observed_before_deadline,
      timing_inconclusive_events: timing_inconclusive }
  end
  { auction_id: id, status: auction.status, bids: bids.length, manual_bids: bids.count { |row| row[3] == "manual" },
    maximum_bids: maxima.length, current_price: auction.current_price,
    leader_id: auction.current_leader_id, winner_id: auction.winner_id,
    public_revision: auction.public_revision, ends_at: auction.ends_at.utc.iso8601(6),
    outbox_pending: OutboxEvent.where(auction_id: id, published_at: nil).count,
    kafka_pending: OutboxEvent.where(auction_id: id, kafka_published_at: nil).count,
    closing: closing_detail }
end

if manifest.fetch("scenario") == "challenge"
  actors = manifest.fetch("users").map { |value| Integer(value) }
  records = IdempotencyRecord.where(actor_id: actors, operation: "place_bid").to_a
  accepted = records.select { |record| record.response_status == 201 }
  failures << "challenge: multiple commands for a bidder" unless records.map(&:actor_id).uniq.length == records.length
  failures << "challenge: unfinished or unexpected command status" unless
    records.all? { |record| record.status == "completed" && [ 201, 422 ].include?(record.response_status) }
  failures << "challenge: completed accepted commands disagree with visible bids" unless
    accepted.length == Bid.where(auction_id: ids.first).count
  accepted.each do |record|
    row = record.response_body&.dig("data")
    failures << "challenge: stored success refers to another bid" unless row &&
      Bid.exists?(id: row["id"], auction_id: ids.first, bidder_id: record.actor_id)
  end
  summaries.first[:challenge_commands] = { completed: records.length,
    accepted: accepted.length, rejected: records.count { |record| record.response_status == 422 } }
end

if %w[duplicate burst].include?(manifest.fetch("scenario"))
  actor = Integer(manifest.fetch("users").first)
  id = ids.first
  digest = Digest::SHA256.hexdigest(manifest.fetch("duplicate_key"))
  records = IdempotencyRecord.where(actor_id: actor, operation: "place_bid", key_digest: digest).to_a
  failures << "duplicate: expected one completed command" unless
    records.length == 1 && records.first.status == "completed" && records.first.response_status == 201
  failures << "duplicate: expected exactly one visible bid" unless Bid.where(auction_id: id).count == 1
  failures << "duplicate: unexpected revision effect" unless Auction.find(id).public_revision == 3
  failures << "duplicate: replay changed deadline" unless Auction.find(id).ends_at == Auction.find(id).original_ends_at
  if records.length == 1 && (visible = Bid.find_by(auction_id: id))
    stored = records.first.response_body&.dig("data")
    failures << "duplicate: stored outcome disagrees with bid" unless
      stored && stored["id"] == visible.id && stored["sequence"] == visible.sequence &&
      stored["amount"] == visible.amount && stored["bidder_id"] == visible.bidder_id
  end
end

result = { run_id: manifest.fetch("run_id"), checked_at: Time.now.utc.iso8601(6),
  auctions: summaries, failures: failures }
puts JSON.generate(result)
exit(1) if failures.any?
