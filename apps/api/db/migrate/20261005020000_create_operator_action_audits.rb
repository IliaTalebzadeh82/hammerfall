class CreateOperatorActionAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_action_audits do |t|
      t.bigint :actor_id, null: false
      t.bigint :auction_id, null: false
      t.string :action, null: false, limit: 40
      t.string :result, null: false, limit: 40
      t.datetime :created_at, null: false
    end

    add_index :operator_action_audits, [ :auction_id, :created_at ]
    add_index :operator_action_audits, [ :actor_id, :created_at ]
    add_foreign_key :operator_action_audits, :users, column: :actor_id
    add_foreign_key :operator_action_audits, :auctions
    add_check_constraint :operator_action_audits, "action IN ('reconcile_projection')", name: "operator_action_audits_action"
    add_check_constraint :operator_action_audits,
      "result IN ('started', 'healthy', 'repaired', 'raced', 'operator_review', 'repair_failed_review', 'failed')",
      name: "operator_action_audits_result"
  end
end
