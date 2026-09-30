# A read-only PostgreSQL consistency check. Redis projection comparison/repair is Phase 12.
class ReconciliationSweepJob
  include Sidekiq::Job
  sidekiq_options queue: "maintenance", retry: 5

  BATCH_SIZE = 100

  def perform(after_id = 0, up_to_id = nil)
    cursor = Integer(after_id)
    raise ArgumentError, "invalid sweep cursor" if cursor.negative?
    ceiling = up_to_id.nil? ? Auction.maximum(:id) : Integer(up_to_id)
    return if ceiling.nil?
    raise ArgumentError, "invalid sweep ceiling" if ceiling.negative?

    rows = ApplicationRecord.connection.select_all(
      Auction.sanitize_sql_array([ <<~SQL, cursor, ceiling, BATCH_SIZE ])
        SELECT a.id, a.status, a.starting_price, a.current_price,
          a.current_leader_id, a.winner_id, b.amount AS last_bid_amount,
          b.bidder_id AS last_bidder_id
        FROM auctions a
        LEFT JOIN LATERAL (
          SELECT amount, bidder_id FROM bids
          WHERE auction_id = a.id ORDER BY sequence DESC LIMIT 1
        ) b ON true
        WHERE a.id > ? AND a.id <= ?
        ORDER BY a.id LIMIT ?
      SQL
    )

    rows.each do |row|
      expected_price = row["last_bid_amount"] || row["starting_price"]
      expected_leader = row["last_bidder_id"]
      consistent = row["current_price"] == expected_price && row["current_leader_id"] == expected_leader
      consistent &&= row["winner_id"] == expected_leader if row["status"] == "closed"
      next if consistent

      Rails.logger.error("auction_reconciliation drift auction_id=#{row['id']} kind=postgresql_state")
    end
    return if rows.length < BATCH_SIZE

    self.class.perform_async(rows.last["id"], ceiling)
  end
end
