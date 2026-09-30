class CreateReconciliationLeases < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_leases do |t|
      t.string :name, null: false
      t.uuid :owner_token, null: false
      t.bigint :cursor, default: 0, null: false
      t.datetime :expires_at, null: false
    end
    add_index :reconciliation_leases, :name, unique: true
    add_check_constraint :reconciliation_leases,
      "name IN ('postgresql_state', 'projection')", name: "reconciliation_leases_known_names"
    add_check_constraint :reconciliation_leases,
      "cursor >= 0", name: "reconciliation_leases_nonnegative_cursor"
  end
end
