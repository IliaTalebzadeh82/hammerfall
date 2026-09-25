class AddAuctionDeadlines < ActiveRecord::Migration[8.1]
  def up
    execute "LOCK TABLE auctions IN ACCESS EXCLUSIVE MODE"
    add_column :auctions, :original_ends_at, :datetime
    add_column :auctions, :closed_at, :datetime
    # Old rows have no closure decision timestamp. This is a documented estimate.
    execute <<~SQL
      UPDATE auctions SET original_ends_at = ends_at,
        closed_at = CASE WHEN status = 'closed' THEN GREATEST(updated_at, ends_at) END
    SQL
    change_column_null :auctions, :original_ends_at, false
    add_check_constraint :auctions, "ends_at >= original_ends_at", name: "auctions_original_deadline"
    add_check_constraint :auctions, "(status = 'closed') = (closed_at IS NOT NULL)", name: "auctions_closure_timestamp"
    add_check_constraint :auctions, "closed_at IS NULL OR closed_at >= ends_at", name: "auctions_closure_after_deadline"
    add_check_constraint :auctions, "status <> 'closed' OR winner_id IS NOT DISTINCT FROM current_leader_id", name: "auctions_final_winner"
    add_index :auctions, [ :ends_at, :id ], where: "status = 'active'", name: "index_auctions_due"
  end

  def down
    if select_value("SELECT COUNT(*) FROM auctions WHERE ends_at <> original_ends_at OR (closed_at IS NOT NULL AND closed_at <> GREATEST(updated_at, ends_at))").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Export Phase 4 deadline/closure history before downgrade"
    end
    remove_index :auctions, name: "index_auctions_due"
    %w[auctions_final_winner auctions_closure_after_deadline auctions_closure_timestamp auctions_original_deadline].each do |name|
      remove_check_constraint :auctions, name: name
    end
    remove_column :auctions, :closed_at
    remove_column :auctions, :original_ends_at
  end
end
