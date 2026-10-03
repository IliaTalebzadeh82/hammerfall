# Rails' controller rate_limit calls #increment on this shared Redis cache.
# RedisCacheStore normally swallows connection failures, so its error handler
# must raise to make each endpoint's outage policy explicit.
class RateLimitStore
  class BackendUnavailable < StandardError; end
  MUTEX = Mutex.new

  def self.for(kind)
    MUTEX.synchronize do
      @stores ||= {}
      @stores[kind] ||= new(kind)
    end
  end

  def self.reset_test!
    raise "Rate limit reset is test-only" unless Rails.env.test?
    self.for(:auth).instance_variable_get(:@redis).clear
    @stores&.each_value { |store| store.instance_variable_get(:@local).clear }
  end

  def initialize(kind, redis: nil, local: nil)
    raise ArgumentError, "Unknown limiter class" unless %i[auth bid privileged cable].include?(kind)
    @kind = kind
    @redis = redis || ActiveSupport::Cache::RedisCacheStore.new(
      **RedisConnectionConfig.build, namespace: "hammerfall:rate-limit:v1",
      connect_timeout: 0.2, read_timeout: 0.2, write_timeout: 0.2,
      error_handler: ->(method:, exception:, returning:) { raise exception }
    )
    @local = local || ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)
  end

  def increment(key, amount = 1, expires_in:)
    count = @redis.increment(key, amount, expires_in: expires_in)
    raise Redis::BaseError, "Redis limiter returned no counter" unless count.is_a?(Integer) && count.positive?
    count
  rescue Redis::BaseError, RedisClient::Error, ConnectionPool::Error, ConnectionPool::TimeoutError
    Observability.counter("hammerfall_security_rate_limits", attributes: { operation: @kind.to_s, result: "degraded" })
    SecurityEvents.emit(category: "rate_limit", outcome: "degraded", reason: "backend_unavailable")
    raise BackendUnavailable, "Rate limiter unavailable" if %i[auth cable].include?(@kind)

    # During outage each process admits at most half its usual quota.
    @local.increment(key, amount * 2, expires_in: expires_in)
  end
end
