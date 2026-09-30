class ConstrainOutboxDomainSnapshot < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :outbox_events, <<~SQL.squish, name: "outbox_events_known_domain_snapshot"
      domain_event_type IS NULL OR
      (domain_event_type IN ('auction.closed.v1', 'auction.status_changed.v1',
        'auction.terms_changed.v1', 'auction.price_changed.v1', 'auction.extended.v1')
        AND jsonb_typeof(domain_payload) = 'object')
    SQL
  end
end
