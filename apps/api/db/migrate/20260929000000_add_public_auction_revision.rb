class AddPublicAuctionRevision < ActiveRecord::Migration[8.1]
  def up
    add_column :auctions, :public_revision, :bigint, null: false, default: 0
    add_check_constraint :auctions, "public_revision >= 0", name: "auctions_public_revision_nonnegative"
  end

  def down
    if select_value("SELECT COUNT(*) FROM auctions WHERE public_revision <> 0").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Preserve public revisions and stop realtime clients before downgrade"
    end
    remove_check_constraint :auctions, name: "auctions_public_revision_nonnegative"
    remove_column :auctions, :public_revision
  end
end
