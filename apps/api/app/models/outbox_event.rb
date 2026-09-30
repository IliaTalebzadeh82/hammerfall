# Public invalidation intent, committed with its auction revision.
class OutboxEvent < ApplicationRecord
  EVENT_TYPE = "auction.changed.v1"

  def self.record_auction_change!(auction_id:, revision:, domain_event_type:, domain_payload:)
    create!(event_type: EVENT_TYPE, schema_version: 1, auction_id: auction_id, public_revision: revision,
      domain_event_type: domain_event_type, domain_payload: domain_payload)
  end

  def self.pending
    where(published_at: nil)
  end

  def self.due
    pending.where("next_attempt_at <= CURRENT_TIMESTAMP")
  end

  def self.kafka_pending
    where(kafka_published_at: nil)
  end

  def self.kafka_due
    kafka_pending.where("kafka_next_attempt_at <= CURRENT_TIMESTAMP")
  end

  def kafka_envelope
    { event_id: event_id, event_type: domain_event_type, schema_version: 1,
      aggregate_id: auction_id, aggregate_version: public_revision,
      occurred_at: occurred_at.utc.iso8601(6), data: domain_payload }
  end
end
