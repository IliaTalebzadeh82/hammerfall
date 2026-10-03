# Keep an unavailable Redis from holding an outbox row lock indefinitely while
# the publisher waits for an enqueue result. Unknown outcomes remain retryable.
require Rails.root.join("lib/observability/sidekiq_middleware")
require Rails.root.join("app/services/redis_connection_config")

Sidekiq.configure_client do |config|
  config.redis = RedisConnectionConfig.build.merge(network_timeout: 2)
  config.client_middleware { |chain| chain.add Observability::SidekiqMiddleware::Client }
end

Sidekiq.configure_server do |config|
  config.redis = RedisConnectionConfig.build.merge(network_timeout: 2)
  config.client_middleware { |chain| chain.add Observability::SidekiqMiddleware::Client }
  config.server_middleware { |chain| chain.add Observability::SidekiqMiddleware::Server }
end
