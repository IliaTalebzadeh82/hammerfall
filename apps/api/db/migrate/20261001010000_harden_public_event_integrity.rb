class HardenPublicEventIntegrity < ActiveRecord::Migration[8.1]
  def change
    change_column_default :outbox_events, :occurred_at, from: -> { "CURRENT_TIMESTAMP" }, to: -> { "clock_timestamp()" }
  end
end
