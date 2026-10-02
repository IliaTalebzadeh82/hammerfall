# Run in the API container with CHAOS_AUCTION_ID set. Public, bounded state only.
require "json"
require "digest"

auction = Auction.find(Integer(ENV.fetch("CHAOS_AUCTION_ID")))
events = OutboxEvent.where(auction_id: auction.id).order(:public_revision)
bids = Bid.where(auction_id: auction.id).order(:sequence).pluck(:sequence, :amount, :bidder_id)
receipts = ConsumedKafkaEvent.where(consumer_name: "hammerfall.audit.v1", auction_id: auction.id)
audits = KafkaAuditEntry.where(consumer_name: "hammerfall.audit.v1", auction_id: auction.id)
event_ids = events.pluck(:event_id)
maximums = MaximumBid.where(auction_id: auction.id)
priorities = maximums.pluck(:priority_sequence)
idempotency = ENV["CHAOS_USER_ID"] ? IdempotencyRecord.where(actor_id: Integer(ENV.fetch("CHAOS_USER_ID"))) : nil
event_delivery = events.map do |event|
  { event_id: event.event_id,
    payload_sha256: Digest::SHA256.hexdigest(JSON.generate(event.kafka_envelope)),
    kafka_acknowledged: event.kafka_published_at.present?, kafka_attempts: event.kafka_attempts,
    audit_receipts: receipts.where(event_id: event.event_id).count,
    audit_effects: audits.where(event_id: event.event_id).count }
end
failures = []
failures << "bid_sequence" unless bids.map(&:first) == (1..bids.size).to_a
expected_price, expected_leader = bids.empty? ? [ auction.starting_price, nil ] : bids.last.drop(1)
failures << "price_or_leader" unless [ auction.current_price, auction.current_leader_id ] ==
  [ expected_price, expected_leader ]
winner_valid = auction.status == "closed" ? auction.winner_id == auction.current_leader_id : auction.winner_id.nil?
failures << "winner" unless winner_valid
failures << "outbox_revisions" unless events.pluck(:public_revision) == (1..auction.public_revision).to_a
failures << "event_identity" unless event_ids.uniq.size == event_ids.size
failures << "audit_duplicate" unless receipts.count == receipts.distinct.count(:event_id) &&
  audits.count == audits.distinct.count(:event_id) && receipts.count == audits.count
failures << "audit_identity" unless receipts.pluck(:event_id).sort == audits.pluck(:event_id).sort &&
  (receipts.pluck(:event_id) - event_ids).empty?

public_data = Api::V1::AuctionPresenter.new(auction).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
result = {
  auction_id: auction.id, public_revision: auction.public_revision,
  public_data: public_data, bid_count: bids.size, last_bid_sequence: bids.last&.first,
  last_bid_id: Bid.where(auction_id: auction.id).order(:sequence).last&.id,
  outbox_count: events.count, sidekiq_pending: events.where(published_at: nil).count,
  kafka_pending: events.where(kafka_published_at: nil).count,
  kafka_retry_count: events.where("kafka_attempts > 1").count,
  sidekiq_retry_count: events.where("attempts > 1").count,
  audit_receipts: receipts.count, audit_effects: audits.count,
  maximum_count: maximums.count, maximum_priorities_unique: priorities.uniq.size == priorities.size,
  idempotency_count: idempotency&.count, idempotency_completed: idempotency&.where(status: "completed")&.count,
  outbox_event_ids: event_ids, latest_event_id: event_ids.last,
  event_delivery: event_delivery, failures: failures
}
puts JSON.generate(result)
exit(1) if failures.any?
