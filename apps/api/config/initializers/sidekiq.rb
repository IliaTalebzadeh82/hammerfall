# Keep an unavailable Redis from holding an outbox row lock indefinitely while
# the publisher waits for an enqueue result. Unknown outcomes remain retryable.
Sidekiq.configure_client do |config|
  config.redis = { network_timeout: 2 }
end
