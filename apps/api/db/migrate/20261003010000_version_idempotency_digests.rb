class VersionIdempotencyDigests < ActiveRecord::Migration[8.1]
  def up
    add_column :idempotency_records, :digest_version, :integer, default: 1, null: false
    add_column :idempotency_records, :digest_key_id, :string, limit: 32
    add_check_constraint :idempotency_records,
      "(digest_version = 1 AND digest_key_id IS NULL) OR (digest_version = 2 AND digest_key_id ~ '^[a-z0-9][a-z0-9_-]{0,31}$')",
      name: "idempotency_digest_version"
    add_index :idempotency_records, [ :digest_version, :digest_key_id ], name: "index_idempotency_records_on_digest_key"
  end

  def down
    if select_value("SELECT COUNT(*) FROM idempotency_records WHERE digest_version = 2").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Prune keyed idempotency outcomes before reverting digest versioning"
    end
    remove_index :idempotency_records, name: "index_idempotency_records_on_digest_key"
    remove_check_constraint :idempotency_records, name: "idempotency_digest_version"
    remove_column :idempotency_records, :digest_key_id
    remove_column :idempotency_records, :digest_version
  end
end
