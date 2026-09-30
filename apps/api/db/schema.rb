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

ActiveRecord::Schema[8.1].define(version: 2026_10_01_011000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "auctions", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "current_leader_id"
    t.bigint "current_price", null: false
    t.text "description", default: "", null: false
    t.datetime "ends_at", null: false
    t.bigint "minimum_increment", null: false
    t.datetime "original_ends_at", null: false
    t.bigint "public_revision", default: 0, null: false
    t.bigint "starting_price", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "draft", null: false
    t.string "title", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.bigint "winner_id"
    t.index ["current_leader_id"], name: "index_auctions_on_current_leader_id"
    t.index ["ends_at", "id"], name: "index_auctions_due", where: "((status)::text = 'active'::text)"
    t.index ["winner_id"], name: "index_auctions_on_winner_id"
    t.check_constraint "(status::text = 'closed'::text) = (closed_at IS NOT NULL)", name: "auctions_closure_timestamp"
    t.check_constraint "closed_at IS NULL OR closed_at >= ends_at", name: "auctions_closure_after_deadline"
    t.check_constraint "current_price >= 1 AND current_price <= '1000000000000'::bigint", name: "auctions_current_price_range"
    t.check_constraint "current_price >= starting_price", name: "auctions_price_floor"
    t.check_constraint "ends_at > starts_at", name: "auctions_time_window"
    t.check_constraint "ends_at >= original_ends_at", name: "auctions_original_deadline"
    t.check_constraint "minimum_increment >= 1 AND minimum_increment <= '1000000000000'::bigint", name: "auctions_minimum_increment_range"
    t.check_constraint "public_revision >= 0", name: "auctions_public_revision_nonnegative"
    t.check_constraint "starting_price >= 1 AND starting_price <= '1000000000000'::bigint", name: "auctions_starting_price_range"
    t.check_constraint "status::text <> 'closed'::text OR NOT winner_id IS DISTINCT FROM current_leader_id", name: "auctions_final_winner"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'scheduled'::character varying, 'active'::character varying, 'closed'::character varying, 'cancelled'::character varying]::text[])", name: "auctions_valid_status"
    t.check_constraint "title::text ~ '[^[:space:]]'::text", name: "auctions_title_present"
    t.check_constraint "winner_id IS NULL OR status::text = 'closed'::text", name: "auctions_winner_only_when_closed"
  end

  create_table "bids", force: :cascade do |t|
    t.bigint "amount", null: false
    t.bigint "auction_id", null: false
    t.bigint "bidder_id", null: false
    t.datetime "created_at", null: false
    t.string "origin", default: "manual", null: false
    t.bigint "sequence", null: false
    t.index ["auction_id", "amount", "id"], name: "index_bids_on_auction_and_leading_amount", order: { amount: :desc }
    t.index ["auction_id", "sequence"], name: "index_bids_on_auction_id_and_sequence", unique: true
    t.index ["bidder_id"], name: "index_bids_on_bidder_id"
    t.check_constraint "amount >= 1 AND amount <= '1000000000000'::bigint", name: "bids_amount_range"
    t.check_constraint "origin::text = ANY (ARRAY['manual'::character varying, 'automatic'::character varying]::text[])", name: "bids_valid_origin"
    t.check_constraint "sequence > 0", name: "bids_sequence_positive"
  end

  create_table "consumed_kafka_events", force: :cascade do |t|
    t.bigint "auction_id", null: false
    t.datetime "consumed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "consumer_name", null: false
    t.uuid "event_id", null: false
    t.string "event_type", null: false
    t.string "payload_digest", limit: 64
    t.bigint "public_revision", null: false
    t.index ["consumer_name", "auction_id", "public_revision"], name: "index_consumed_kafka_events_revision", unique: true
    t.index ["consumer_name", "event_id"], name: "index_consumed_kafka_events_identity", unique: true
    t.check_constraint "auction_id > 0 AND public_revision > 0", name: "consumed_kafka_events_positive_values"
    t.check_constraint "payload_digest IS NULL OR payload_digest::text ~ '^[0-9a-f]{64}$'::text", name: "consumed_kafka_events_payload_digest"
  end

  create_table "idempotency_records", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "expires_at", null: false
    t.string "key_digest", limit: 64, null: false
    t.string "operation", null: false
    t.string "request_fingerprint", limit: 64, null: false
    t.jsonb "response_body"
    t.integer "response_status"
    t.string "status", default: "processing", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["actor_id", "operation", "key_digest"], name: "index_idempotency_records_on_scope", unique: true
    t.index ["expires_at", "id"], name: "index_idempotency_records_for_pruning", where: "((status)::text = 'completed'::text)"
    t.check_constraint "expires_at > created_at", name: "idempotency_retention"
    t.check_constraint "key_digest::text ~ '^[0-9a-f]{64}$'::text AND request_fingerprint::text ~ '^[0-9a-f]{64}$'::text", name: "idempotency_digests"
    t.check_constraint "operation::text = ANY (ARRAY['place_bid'::character varying, 'set_maximum_bid'::character varying]::text[])", name: "idempotency_operation"
    t.check_constraint "status::text = 'processing'::text AND response_status IS NULL AND response_body IS NULL OR status::text = 'completed'::text AND (response_status = ANY (ARRAY[200, 201, 404, 422])) AND response_status IS NOT NULL AND response_body IS NOT NULL AND jsonb_typeof(response_body) = 'object'::text", name: "idempotency_outcome"
  end

  create_table "kafka_audit_entries", force: :cascade do |t|
    t.string "arrival_order", null: false
    t.bigint "auction_id", null: false
    t.string "consumer_name", null: false
    t.uuid "event_id", null: false
    t.string "event_type", null: false
    t.bigint "public_revision", null: false
    t.datetime "recorded_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["consumer_name", "auction_id", "public_revision"], name: "index_kafka_audit_entries_revision", unique: true
    t.index ["consumer_name", "event_id"], name: "index_kafka_audit_entries_identity", unique: true
    t.check_constraint "arrival_order::text = ANY (ARRAY['first'::character varying, 'next'::character varying, 'gap'::character varying, 'stale'::character varying]::text[])", name: "kafka_audit_entries_arrival_order"
  end

  create_table "maximum_bids", force: :cascade do |t|
    t.bigint "auction_id", null: false
    t.bigint "bidder_id", null: false
    t.datetime "created_at", null: false
    t.bigint "maximum_amount", null: false
    t.bigint "priority_sequence", null: false
    t.datetime "updated_at", null: false
    t.index ["auction_id", "bidder_id"], name: "index_maximum_bids_on_auction_id_and_bidder_id", unique: true
    t.index ["auction_id", "priority_sequence"], name: "index_maximum_bids_on_auction_id_and_priority_sequence", unique: true
    t.index ["bidder_id"], name: "index_maximum_bids_on_bidder_id"
    t.check_constraint "maximum_amount >= 1 AND maximum_amount <= '1000000000000'::bigint", name: "maximum_bids_amount_range"
    t.check_constraint "priority_sequence > 0", name: "maximum_bids_priority_positive"
  end

  create_table "outbox_events", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.bigint "auction_id", null: false
    t.string "domain_event_type"
    t.jsonb "domain_payload"
    t.uuid "event_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "event_type", null: false
    t.integer "kafka_attempts", default: 0, null: false
    t.string "kafka_last_error"
    t.datetime "kafka_next_attempt_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "kafka_published_at"
    t.string "last_error"
    t.datetime "next_attempt_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "occurred_at", default: -> { "clock_timestamp()" }, null: false
    t.bigint "public_revision", null: false
    t.datetime "published_at"
    t.integer "schema_version", null: false
    t.index ["auction_id", "public_revision"], name: "index_outbox_events_on_auction_id_and_public_revision", unique: true
    t.index ["event_id"], name: "index_outbox_events_on_event_id", unique: true
    t.index ["kafka_next_attempt_at", "id"], name: "index_outbox_events_kafka_due", where: "(kafka_published_at IS NULL)"
    t.index ["next_attempt_at", "id"], name: "index_outbox_events_due", where: "(published_at IS NULL)"
    t.check_constraint "auction_id > 0 AND public_revision > 0 AND attempts >= 0", name: "outbox_events_positive_values"
    t.check_constraint "domain_event_type IS NULL AND domain_payload IS NULL AND kafka_published_at IS NOT NULL OR domain_event_type IS NOT NULL AND domain_payload IS NOT NULL", name: "outbox_events_domain_payload_pair"
    t.check_constraint "domain_event_type IS NULL OR (domain_event_type::text = ANY (ARRAY['auction.closed.v1'::character varying, 'auction.status_changed.v1'::character varying, 'auction.terms_changed.v1'::character varying, 'auction.price_changed.v1'::character varying, 'auction.extended.v1'::character varying]::text[])) AND jsonb_typeof(domain_payload) = 'object'::text", name: "outbox_events_known_domain_snapshot"
    t.check_constraint "event_type::text = 'auction.changed.v1'::text AND schema_version = 1", name: "outbox_events_known_version"
    t.check_constraint "kafka_attempts >= 0", name: "outbox_events_kafka_attempts_nonnegative"
  end

  create_table "reconciliation_leases", force: :cascade do |t|
    t.bigint "cursor", default: 0, null: false
    t.datetime "expires_at", null: false
    t.string "name", null: false
    t.uuid "owner_token", null: false
    t.index ["name"], name: "index_reconciliation_leases_on_name", unique: true
    t.check_constraint "cursor >= 0", name: "reconciliation_leases_nonnegative_cursor"
    t.check_constraint "name::text = ANY (ARRAY['postgresql_state'::character varying, 'projection'::character varying]::text[])", name: "reconciliation_leases_known_names"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.check_constraint "name::text ~ '[^[:space:]]'::text", name: "users_name_present"
  end

  add_foreign_key "auctions", "users", column: "current_leader_id"
  add_foreign_key "auctions", "users", column: "winner_id"
  add_foreign_key "bids", "auctions"
  add_foreign_key "bids", "users", column: "bidder_id"
  add_foreign_key "idempotency_records", "users", column: "actor_id"
  add_foreign_key "maximum_bids", "auctions"
  add_foreign_key "maximum_bids", "users", column: "bidder_id"
end
