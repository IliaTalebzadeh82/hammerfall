class AddAuctionClosingPolicy < ActiveRecord::Migration[8.1]
  def up
    add_column :auctions, :closing_policy, :string, null: false, default: "regular"
    add_check_constraint :auctions, "closing_policy IN ('regular', 'rapid')", name: "auctions_valid_closing_policy"
  end

  def down
    if select_value("SELECT 1 FROM auctions WHERE closing_policy = 'rapid' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "rapid auctions require an explicit policy migration before rollback"
    end
    if select_value("SELECT 1 FROM outbox_events WHERE domain_payload ? 'closing_policy' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "closing-policy events require a reader migration before rollback"
    end

    remove_check_constraint :auctions, name: "auctions_valid_closing_policy"
    remove_column :auctions, :closing_policy
  end
end
