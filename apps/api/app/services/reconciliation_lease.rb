require "securerandom"

# PostgreSQL-backed maintenance ownership. Never consulted by auction commands.
class ReconciliationLease
  DURATION = "10 minutes".freeze
  HEARTBEAT_ROWS = 25
  POSTGRESQL_STATE = "postgresql_state".freeze
  PROJECTION = "projection".freeze

  def self.claim(name)
    token = SecureRandom.uuid
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, name, token ])
      INSERT INTO reconciliation_leases (name, owner_token, cursor, expires_at)
      VALUES (?, ?::uuid, 0, clock_timestamp() + interval '#{DURATION}')
      ON CONFLICT (name) DO UPDATE
        SET owner_token = EXCLUDED.owner_token, cursor = 0, expires_at = EXCLUDED.expires_at
      WHERE reconciliation_leases.expires_at <= clock_timestamp()
      RETURNING owner_token
    SQL
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.select_value(sql)&.to_s
    end
  end

  def self.renew(name, token, cursor)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, name, token, cursor ])
      UPDATE reconciliation_leases
      SET expires_at = clock_timestamp() + interval '#{DURATION}'
      WHERE name = ? AND owner_token = ?::uuid AND cursor = ? AND expires_at > clock_timestamp()
      RETURNING owner_token
    SQL
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.select_value(sql).present?
    end
  end

  def self.advance(name, token, cursor, next_cursor)
    raise ArgumentError, "cursor must advance" unless next_cursor > cursor

    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, next_cursor, name, token, cursor ])
      UPDATE reconciliation_leases
      SET cursor = ?, expires_at = clock_timestamp() + interval '#{DURATION}'
      WHERE name = ? AND owner_token = ?::uuid AND cursor = ? AND expires_at > clock_timestamp()
      RETURNING cursor
    SQL
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.select_value(sql) == next_cursor
    end
  end

  def self.release(name, token, cursor = nil)
    sql = ApplicationRecord.sanitize_sql_array([ <<~SQL, name, token, cursor, cursor ])
      DELETE FROM reconciliation_leases
      WHERE name = ? AND owner_token = ?::uuid AND (? IS NULL OR cursor = ?)
    SQL
    ApplicationRecord.connection_pool.with_connection { |connection| connection.delete(sql) == 1 }
  end
end
