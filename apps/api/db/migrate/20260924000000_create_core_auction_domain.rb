class CreateCoreAuctionDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false, limit: 100
      t.timestamps
    end
    add_check_constraint :users, "name ~ '[^[:space:]]'", name: "users_name_present"

    create_table :auctions do |t|
      t.string :title, null: false, limit: 200
      t.text :description, null: false, default: ""
      t.string :status, null: false, default: "draft"
      t.bigint :starting_price, null: false
      t.bigint :current_price, null: false
      t.bigint :minimum_increment, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.references :winner, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_check_constraint :auctions, "title ~ '[^[:space:]]'", name: "auctions_title_present"
    add_check_constraint :auctions, "status IN ('draft', 'scheduled', 'active', 'closed', 'cancelled')", name: "auctions_valid_status"
    %w[starting_price current_price minimum_increment].each do |column|
      add_check_constraint :auctions, "#{column} BETWEEN 1 AND 1000000000000", name: "auctions_#{column}_range"
    end
    add_check_constraint :auctions, "current_price >= starting_price", name: "auctions_price_floor"
    add_check_constraint :auctions, "ends_at > starts_at", name: "auctions_time_window"
    add_check_constraint :auctions, "winner_id IS NULL OR status = 'closed'", name: "auctions_winner_only_when_closed"

    create_table :bids do |t|
      t.references :auction, null: false, foreign_key: true, index: false
      t.references :bidder, null: false, foreign_key: { to_table: :users }
      t.bigint :amount, null: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :bids, "amount BETWEEN 1 AND 1000000000000", name: "bids_amount_range"
    add_index :bids, [ :auction_id, :id ]
    add_index :bids, [ :auction_id, :amount, :id ], order: { amount: :desc, id: :asc }, name: "index_bids_on_auction_and_leading_amount"
  end
end
