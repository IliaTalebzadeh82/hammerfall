class HealthController < ApplicationController
  # Readiness is limited to the authoritative store. Redis, Kafka and workers
  # may be degraded while the API can still commit and read auction state.
  def ready
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") }
    head :ok
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::StatementInvalid
    head :service_unavailable
  end
end
