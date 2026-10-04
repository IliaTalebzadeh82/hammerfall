class AddHiddenAuctionReserve < ActiveRecord::Migration[8.1]
  def up
    add_column :auctions, :reserve_price, :bigint
    add_check_constraint :auctions,
      "reserve_price IS NULL OR (reserve_price BETWEEN 1 AND 1000000000000 AND reserve_price >= starting_price)",
      name: "auctions_reserve_price_range"

    remove_check_constraint :auctions, name: "auctions_final_winner"
    add_check_constraint :auctions,
      "status <> 'closed' OR winner_id IS NOT DISTINCT FROM CASE WHEN current_leader_id IS NOT NULL AND (reserve_price IS NULL OR current_price >= reserve_price) THEN current_leader_id ELSE NULL END",
      name: "auctions_final_winner"

    remove_check_constraint :outbox_events, name: "outbox_events_known_version"
    add_check_constraint :outbox_events,
      "event_type = 'auction.changed.v1' AND schema_version IN (1, 2)",
      name: "outbox_events_known_version"
    remove_check_constraint :outbox_events, name: "outbox_events_known_domain_snapshot"
    add_check_constraint :outbox_events,
      "domain_event_type IS NULL OR (domain_event_type IN ('auction.closed.v1', 'auction.status_changed.v1', 'auction.terms_changed.v1', 'auction.price_changed.v1', 'auction.extended.v1', 'auction.closed.v2', 'auction.status_changed.v2', 'auction.terms_changed.v2', 'auction.price_changed.v2', 'auction.extended.v2') AND domain_event_type LIKE ('%.v' || schema_version) AND jsonb_typeof(domain_payload) = 'object')",
      name: "outbox_events_known_domain_snapshot"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "reserve data exists" if select_value("SELECT EXISTS (SELECT 1 FROM auctions WHERE reserve_price IS NOT NULL)")
    raise ActiveRecord::IrreversibleMigration, "v2 outbox data exists" if select_value("SELECT EXISTS (SELECT 1 FROM outbox_events WHERE schema_version = 2)")

    remove_check_constraint :outbox_events, name: "outbox_events_known_domain_snapshot"
    add_check_constraint :outbox_events,
      "domain_event_type IS NULL OR (domain_event_type IN ('auction.closed.v1', 'auction.status_changed.v1', 'auction.terms_changed.v1', 'auction.price_changed.v1', 'auction.extended.v1') AND jsonb_typeof(domain_payload) = 'object')",
      name: "outbox_events_known_domain_snapshot"
    remove_check_constraint :outbox_events, name: "outbox_events_known_version"
    add_check_constraint :outbox_events, "event_type = 'auction.changed.v1' AND schema_version = 1", name: "outbox_events_known_version"
    remove_check_constraint :auctions, name: "auctions_final_winner"
    add_check_constraint :auctions, "status <> 'closed' OR winner_id IS NOT DISTINCT FROM current_leader_id", name: "auctions_final_winner"
    remove_check_constraint :auctions, name: "auctions_reserve_price_range"
    remove_column :auctions, :reserve_price
  end
end
