# Bypass the Rails query cache: a cached SELECT would turn wall-clock into stale time.
class AuctionClock
  def self.now
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.uncached { connection.select_value("SELECT clock_timestamp()") }
    end
  end
end
