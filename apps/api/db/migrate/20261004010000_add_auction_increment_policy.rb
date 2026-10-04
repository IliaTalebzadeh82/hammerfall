class AddAuctionIncrementPolicy < ActiveRecord::Migration[8.1]
  def up
    add_column :auctions, :increment_policy, :string, null: false, default: "fixed"
    add_check_constraint :auctions, "increment_policy IN ('fixed', 'stepped')", name: "auctions_valid_increment_policy"
  end

  def down
    if select_value("SELECT 1 FROM auctions WHERE increment_policy = 'stepped' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "stepped auctions require an explicit policy migration before rollback"
    end

    remove_check_constraint :auctions, name: "auctions_valid_increment_policy"
    remove_column :auctions, :increment_policy
  end
end
