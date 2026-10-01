class ConstrainOriginalAuctionWindow < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :auctions, "original_ends_at > starts_at", name: "auctions_original_window"
  end
end
