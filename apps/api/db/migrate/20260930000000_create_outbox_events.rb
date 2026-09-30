class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events do |t|
      t.uuid :event_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :event_type, null: false
      t.integer :schema_version, null: false
      t.bigint :auction_id, null: false
      t.bigint :public_revision, null: false
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :published_at
      t.datetime :next_attempt_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.integer :attempts, null: false, default: 0
      t.string :last_error
    end

    add_index :outbox_events, :event_id, unique: true
    add_index :outbox_events, [ :auction_id, :public_revision ], unique: true
    add_index :outbox_events, [ :next_attempt_at, :id ], where: "published_at IS NULL", name: "index_outbox_events_due"
    add_check_constraint :outbox_events, "event_type = 'auction.changed.v1' AND schema_version = 1", name: "outbox_events_known_version"
    add_check_constraint :outbox_events, "auction_id > 0 AND public_revision > 0 AND attempts >= 0", name: "outbox_events_positive_values"
  end
end
