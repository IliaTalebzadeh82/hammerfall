class AddMaximumBidding < ActiveRecord::Migration[8.1]
  def up
    execute "LOCK TABLE auctions, bids IN ACCESS EXCLUSIVE MODE"
    add_reference :auctions, :current_leader, foreign_key: { to_table: :users }
    execute <<~SQL
      UPDATE auctions SET current_leader_id = latest.bidder_id
      FROM (SELECT DISTINCT ON (auction_id) auction_id, bidder_id
            FROM bids ORDER BY auction_id, sequence DESC) latest
      WHERE auctions.id = latest.auction_id
    SQL
    add_column :bids, :origin, :string, null: false, default: "manual"
    add_check_constraint :bids, "origin IN ('manual', 'automatic')", name: "bids_valid_origin"
    create_table :maximum_bids do |t|
      t.references :auction, null: false, foreign_key: true, index: false
      t.references :bidder, null: false, foreign_key: { to_table: :users }
      t.bigint :maximum_amount, null: false
      t.bigint :priority_sequence, null: false
      t.timestamps
    end
    add_index :maximum_bids, [ :auction_id, :bidder_id ], unique: true
    add_index :maximum_bids, [ :auction_id, :priority_sequence ], unique: true
    add_check_constraint :maximum_bids, "maximum_amount BETWEEN 1 AND 1000000000000", name: "maximum_bids_amount_range"
    add_check_constraint :maximum_bids, "priority_sequence > 0", name: "maximum_bids_priority_positive"
  end

  def down
    # Private commitments cannot be reconstructed after downgrade. Refuse data loss.
    if select_value("SELECT COUNT(*) FROM maximum_bids").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Remove private commitments only through an explicit data migration before downgrade"
    end
    drop_table :maximum_bids
    remove_check_constraint :bids, name: "bids_valid_origin"
    remove_column :bids, :origin
    remove_reference :auctions, :current_leader, foreign_key: { to_table: :users }
  end
end
