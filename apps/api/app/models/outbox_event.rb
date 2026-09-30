# Public invalidation intent, committed with its auction revision.
class OutboxEvent < ApplicationRecord
  EVENT_TYPE = "auction.changed.v1"

  def self.record_auction_change!(auction_id:, revision:)
    create!(event_type: EVENT_TYPE, schema_version: 1, auction_id: auction_id, public_revision: revision)
  end

  def self.pending
    where(published_at: nil)
  end

  def self.due
    pending.where("next_attempt_at <= CURRENT_TIMESTAMP")
  end
end
