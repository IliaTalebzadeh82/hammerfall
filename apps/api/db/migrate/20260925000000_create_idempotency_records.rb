class CreateIdempotencyRecords < ActiveRecord::Migration[8.1]
  def up
    create_table :idempotency_records do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }, index: false
      t.string :operation, null: false
      # A digest avoids retaining/logging the client's potentially sensitive key.
      t.string :key_digest, limit: 64, null: false
      t.string :request_fingerprint, limit: 64, null: false
      t.string :status, null: false, default: "processing"
      t.integer :response_status
      t.jsonb :response_body
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :idempotency_records, [ :actor_id, :operation, :key_digest ], unique: true, name: "index_idempotency_records_on_scope"
    add_index :idempotency_records, [ :expires_at, :id ], where: "status = 'completed'", name: "index_idempotency_records_for_pruning"
    add_check_constraint :idempotency_records, "operation IN ('place_bid', 'set_maximum_bid')", name: "idempotency_operation"
    add_check_constraint :idempotency_records, "key_digest ~ '^[0-9a-f]{64}$' AND request_fingerprint ~ '^[0-9a-f]{64}$'", name: "idempotency_digests"
    add_check_constraint :idempotency_records, <<~SQL.squish, name: "idempotency_outcome"
      (status = 'processing' AND response_status IS NULL AND response_body IS NULL)
      OR (status = 'completed' AND response_status IN (200, 201, 404, 422)
          AND response_status IS NOT NULL AND response_body IS NOT NULL
          AND jsonb_typeof(response_body) = 'object')
    SQL
    add_check_constraint :idempotency_records, "expires_at > created_at", name: "idempotency_retention"
  end

  def down
    if select_value("SELECT COUNT(*) FROM idempotency_records").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Preserve retained idempotency outcomes before downgrade"
    end
    drop_table :idempotency_records
  end
end
