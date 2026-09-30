# Receipt and audit entry commit together. Neither table participates in auction decisions.
class ConsumedKafkaEvent < ApplicationRecord
  def self.record!(consumer_name:, event:, payload_digest:)
    transaction do
      existing = find_by(consumer_name: consumer_name, event_id: event.fetch("event_id"))
      if existing
        raise KafkaEventCodec::InvalidEvent, "event ID reused with different payload" if existing.payload_digest && existing.payload_digest != payload_digest
        return :duplicate
      end

      auction_id = event.fetch("aggregate_id")
      revision = event.fetch("aggregate_version")
      latest = where(consumer_name: consumer_name, auction_id: auction_id).maximum(:public_revision)
      order = if latest.nil?
        "first"
      elsif revision <= latest
        "stale"
      elsif revision == latest + 1
        "next"
      else
        "gap"
      end
      attributes = { consumer_name: consumer_name, event_id: event.fetch("event_id"), auction_id: auction_id,
        public_revision: revision, event_type: event.fetch("event_type") }
      create!(**attributes, payload_digest: payload_digest)
      KafkaAuditEntry.create!(**attributes, arrival_order: order)
      order.to_sym
    end
  rescue ActiveRecord::RecordNotUnique
    # A second group member can race during a rebalance. The unique database
    # key serializes the effect; the loser verifies the winner's identity.
    existing = find_by(consumer_name: consumer_name, event_id: event.fetch("event_id"))
    return :duplicate if existing && (existing.payload_digest.nil? || existing.payload_digest == payload_digest)

    raise KafkaEventCodec::InvalidEvent, "revision or event ID reused with different payload"
  end
end
