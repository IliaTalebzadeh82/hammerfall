# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_24_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "auctions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_price", null: false
    t.text "description", default: "", null: false
    t.datetime "ends_at", null: false
    t.bigint "minimum_increment", null: false
    t.bigint "starting_price", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "draft", null: false
    t.string "title", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.bigint "winner_id"
    t.index ["winner_id"], name: "index_auctions_on_winner_id"
    t.check_constraint "current_price >= 1 AND current_price <= '1000000000000'::bigint", name: "auctions_current_price_range"
    t.check_constraint "current_price >= starting_price", name: "auctions_price_floor"
    t.check_constraint "ends_at > starts_at", name: "auctions_time_window"
    t.check_constraint "minimum_increment >= 1 AND minimum_increment <= '1000000000000'::bigint", name: "auctions_minimum_increment_range"
    t.check_constraint "starting_price >= 1 AND starting_price <= '1000000000000'::bigint", name: "auctions_starting_price_range"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'scheduled'::character varying, 'active'::character varying, 'closed'::character varying, 'cancelled'::character varying]::text[])", name: "auctions_valid_status"
    t.check_constraint "title::text ~ '[^[:space:]]'::text", name: "auctions_title_present"
    t.check_constraint "winner_id IS NULL OR status::text = 'closed'::text", name: "auctions_winner_only_when_closed"
  end

  create_table "bids", force: :cascade do |t|
    t.bigint "amount", null: false
    t.bigint "auction_id", null: false
    t.bigint "bidder_id", null: false
    t.datetime "created_at", null: false
    t.index ["auction_id", "amount", "id"], name: "index_bids_on_auction_and_leading_amount", order: { amount: :desc }
    t.index ["auction_id", "id"], name: "index_bids_on_auction_id_and_id"
    t.index ["bidder_id"], name: "index_bids_on_bidder_id"
    t.check_constraint "amount >= 1 AND amount <= '1000000000000'::bigint", name: "bids_amount_range"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.check_constraint "name::text ~ '[^[:space:]]'::text", name: "users_name_present"
  end

  add_foreign_key "auctions", "users", column: "winner_id"
  add_foreign_key "bids", "auctions"
  add_foreign_key "bids", "users", column: "bidder_id"
end
