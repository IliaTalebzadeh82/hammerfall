class AddAuthoritativeBidSequence < ActiveRecord::Migration[8.1]
  def up
    # Maintenance rollout: stop old writers before migrating and deploying code.
    execute "LOCK TABLE auctions, bids IN ACCESS EXCLUSIVE MODE"
    add_column :bids, :sequence, :bigint
    execute <<~SQL
      UPDATE bids SET sequence = ordered.position
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY auction_id ORDER BY id) AS position
        FROM bids
      ) ordered WHERE bids.id = ordered.id
    SQL
    change_column_null :bids, :sequence, false
    add_check_constraint :bids, "sequence > 0", name: "bids_sequence_positive"
    add_index :bids, [ :auction_id, :sequence ], unique: true
    remove_index :bids, [ :auction_id, :id ]
  end

  def down
    add_index :bids, [ :auction_id, :id ]
    remove_index :bids, [ :auction_id, :sequence ]
    remove_check_constraint :bids, name: "bids_sequence_positive"
    remove_column :bids, :sequence
  end
end
