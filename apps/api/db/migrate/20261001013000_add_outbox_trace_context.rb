class AddOutboxTraceContext < ActiveRecord::Migration[8.1]
  def change
    add_column :outbox_events, :traceparent, :string, limit: 55
    add_column :outbox_events, :tracestate, :string, limit: 512
  end
end
