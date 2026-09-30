class AddKafkaToOutbox < ActiveRecord::Migration[8.1]
  def change
    add_column :outbox_events, :domain_event_type, :string
    add_column :outbox_events, :domain_payload, :jsonb
    add_column :outbox_events, :kafka_published_at, :datetime
    add_column :outbox_events, :kafka_next_attempt_at, :datetime, default: -> { "CURRENT_TIMESTAMP" }, null: false
    add_column :outbox_events, :kafka_attempts, :integer, default: 0, null: false
    add_column :outbox_events, :kafka_last_error, :string

    # Historical invalidations lack a domain snapshot. Never invent one from
    # today's auction state and label it as an event from a past revision.
    reversible do |direction|
      direction.up do
        execute "UPDATE outbox_events SET kafka_published_at = clock_timestamp() WHERE domain_event_type IS NULL"
      end
    end
    add_check_constraint :outbox_events, "kafka_attempts >= 0", name: "outbox_events_kafka_attempts_nonnegative"
    add_check_constraint :outbox_events, "(domain_event_type IS NULL AND domain_payload IS NULL AND kafka_published_at IS NOT NULL) OR (domain_event_type IS NOT NULL AND domain_payload IS NOT NULL)", name: "outbox_events_domain_payload_pair"
    add_index :outbox_events, [ :kafka_next_attempt_at, :id ], where: "kafka_published_at IS NULL", name: "index_outbox_events_kafka_due"

    create_table :consumed_kafka_events do |t|
      t.string :consumer_name, null: false
      t.uuid :event_id, null: false
      t.bigint :auction_id, null: false
      t.bigint :public_revision, null: false
      t.string :event_type, null: false
      t.datetime :consumed_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :consumed_kafka_events, [ :consumer_name, :event_id ], unique: true, name: "index_consumed_kafka_events_identity"
    add_index :consumed_kafka_events, [ :consumer_name, :auction_id, :public_revision ], unique: true, name: "index_consumed_kafka_events_revision"
    add_check_constraint :consumed_kafka_events, "auction_id > 0 AND public_revision > 0", name: "consumed_kafka_events_positive_values"

    create_table :kafka_audit_entries do |t|
      t.string :consumer_name, null: false
      t.uuid :event_id, null: false
      t.bigint :auction_id, null: false
      t.bigint :public_revision, null: false
      t.string :event_type, null: false
      t.string :arrival_order, null: false
      t.datetime :recorded_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :kafka_audit_entries, [ :consumer_name, :event_id ], unique: true, name: "index_kafka_audit_entries_identity"
    add_index :kafka_audit_entries, [ :consumer_name, :auction_id, :public_revision ], unique: true, name: "index_kafka_audit_entries_revision"
    add_check_constraint :kafka_audit_entries, "arrival_order IN ('first', 'next', 'gap', 'stale')", name: "kafka_audit_entries_arrival_order"
  end
end
