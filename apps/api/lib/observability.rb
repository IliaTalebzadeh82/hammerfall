require "json"
require "socket"
require "uri"

# Passive diagnostics. Every call around domain work must run the domain block
# exactly once, even if an SDK hook fails before or after it.
module Observability
  SERVICE_NAMES = {
    "rails" => "hammerfall-api",
    "sidekiq" => "hammerfall-sidekiq",
    "auction_closer" => "hammerfall-auction-closer",
    "outbox_publisher" => "hammerfall-outbox-publisher",
    "kafka_outbox_publisher" => "hammerfall-kafka-outbox-publisher",
    "kafka_audit_consumer" => "hammerfall-kafka-audit-consumer",
    "kafka_projection_consumer" => "hammerfall-kafka-projection-consumer",
    "reconciliation_scheduler" => "hammerfall-reconciliation-scheduler"
  }.freeze
  DURATION_BOUNDARIES = [ 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30 ].freeze
  METRICS = {
    "hammerfall_bid_requests" => [ :counter, %w[operation] ],
    "hammerfall_bid_accepted" => [ :counter, %w[operation] ],
    "hammerfall_bid_rejected" => [ :counter, %w[operation reason] ],
    "hammerfall_bid_processing_duration" => [ :histogram, %w[operation result] ],
    "hammerfall_auction_lock_wait_duration" => [ :histogram, %w[operation] ],
    "hammerfall_auction_extensions" => [ :counter, [] ],
    "hammerfall_auction_close_lag" => [ :histogram, [] ],
    "hammerfall_http_requests" => [ :counter, %w[route method status_class] ],
    "hammerfall_http_duration" => [ :histogram, %w[route method status_class] ],
    "hammerfall_outbox_publish_attempts" => [ :counter, %w[channel] ],
    "hammerfall_outbox_retry_attempts" => [ :counter, %w[channel] ],
    "hammerfall_outbox_publish_failures" => [ :counter, %w[channel] ],
    "hammerfall_outbox_publish_duration" => [ :histogram, %w[channel] ],
    "hammerfall_outbox_pending_events" => [ :gauge, %w[channel] ],
    "hammerfall_outbox_oldest_event_age" => [ :gauge, %w[channel] ],
    "hammerfall_sidekiq_queue_depth" => [ :gauge, %w[queue] ],
    "hammerfall_sidekiq_jobs" => [ :counter, %w[queue result] ],
    "hammerfall_sidekiq_job_duration" => [ :histogram, %w[queue result] ],
    "hammerfall_kafka_consumed" => [ :counter, %w[consumer_group result] ],
    "hammerfall_kafka_consumer_lag" => [ :gauge, %w[consumer_group partition] ],
    "hammerfall_projection_writes" => [ :counter, %w[result] ],
    "hammerfall_projection_checks" => [ :counter, [] ],
    "hammerfall_projection_drift" => [ :counter, %w[kind] ],
    "hammerfall_projection_repair_attempts" => [ :counter, [] ],
    "hammerfall_projection_repairs" => [ :counter, [] ],
    "hammerfall_projection_repair_failures" => [ :counter, [] ],
    "hammerfall_projection_operator_review" => [ :counter, %w[kind] ],
    "hammerfall_projection_batch_size" => [ :histogram, [] ],
    "hammerfall_projection_scan_duration" => [ :histogram, [] ],
    "hammerfall_projection_stale_age" => [ :histogram, %w[source] ],
    "hammerfall_websocket_broadcasts" => [ :counter, %w[result] ],
    "hammerfall_websocket_server_broadcast_lag" => [ :histogram, [] ]
  }.freeze
  OPERATIONS = %w[place_bid set_maximum_bid close edit schedule activate cancel].freeze
  RESULTS = %w[accepted rejected replayed error first next gap stale duplicate applied conflict redis_failure succeeded failed].freeze
  CHANNELS = %w[sidekiq kafka].freeze
  QUEUES = %w[notifications maintenance default].freeze
  CONSUMER_GROUPS = %w[hammerfall.audit.v1 hammerfall.projection.v1].freeze
  DRIFT_KINDS = %w[missing behind conflict corrupt ahead unavailable].freeze
  PROJECTION_SOURCES = %w[kafka postgresql_seed].freeze
  REASONS = %w[auction_ended auction_not_open bid_too_low invalid_auction_state
    maximum_bid_cannot_decrease maximum_bid_too_low validation_failed
    idempotency_key_required invalid_idempotency_key idempotency_key_conflict
    auction_not_found user_not_found invalid_request other].freeze
  EVENT_TYPES = %w[auction.closed.v1 auction.status_changed.v1 auction.terms_changed.v1
    auction.price_changed.v1 auction.extended.v1].freeze
  ROUTES = %w[/up /api/v1/users /api/v1/auctions /api/v1/auctions/:id
    /api/v1/auctions/:id/public-state /api/v1/auctions/:id/maximum-bid
    /api/v1/auctions/:id/bids /api/v1/auctions/:id/schedule
    /api/v1/auctions/:id/activate /api/v1/auctions/:id/close
    /api/v1/auctions/:id/cancel /cable other].freeze
  LOG_FIELDS = %w[operation component result error_class auction_status event_type
    consumer_group partition offset retry_count public_revision auction_id event_id].freeze
  SPAN_FIELDS = %w[hammerfall.operation hammerfall.event_type http.request.method http.route].freeze

  class << self
    attr_reader :service_name

    def enabled?
      @enabled == true
    end

    def configure!
      setting = ENV.fetch("OTEL_ENABLED", "false")
      raise ArgumentError, "invalid OTEL_ENABLED" unless %w[true false].include?(setting)
      return unless setting == "true"

      require "opentelemetry/sdk"
      require "opentelemetry-metrics-sdk"
      require "opentelemetry/exporter/otlp"
      require "opentelemetry/exporter/otlp_metrics"

      endpoint = ENV.fetch("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:4318")
      uri = URI.parse(endpoint)
      raise ArgumentError, "invalid collector endpoint" unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && [ "", "/" ].include?(uri.path)

      ratio = Float(ENV.fetch("OTEL_SAMPLE_RATIO", Rails.env.production? ? "0.1" : "1"))
      raise ArgumentError, "invalid sampling ratio" unless (0.0..1.0).cover?(ratio)

      @service_name = SERVICE_NAMES.fetch(File.basename($PROGRAM_NAME), "hammerfall-api")
      ENV["OTEL_PROPAGATORS"] = "tracecontext"
      ENV["OTEL_TRACES_SAMPLER"] = "parentbased_traceidratio"
      ENV["OTEL_TRACES_SAMPLER_ARG"] = ratio.to_s
      endpoint = endpoint.delete_suffix("/")
      trace_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: "#{endpoint}/v1/traces", timeout: 1)
      metric_exporter = OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(endpoint: "#{endpoint}/v1/metrics", timeout: 1,
        aggregation_cardinality_limit: 200)
      OpenTelemetry::SDK.configure do |config|
        config.service_name = @service_name
        environment = %w[development test production].include?(Rails.env.to_s) ? Rails.env.to_s : "other"
        config.resource = OpenTelemetry::SDK::Resources::Resource.create(
          "deployment.environment" => environment,
          "service.instance.id" => "#{Socket.gethostname}:#{Process.pid}")
        config.add_span_processor(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(trace_exporter,
          exporter_timeout: 1000, schedule_delay: 1000, max_queue_size: 1024, max_export_batch_size: 256))
        config.add_metric_reader(OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
          exporter: metric_exporter, export_interval_millis: 15_000, export_timeout_millis: 1000,
          aggregation_cardinality_limit: 200))
      end
      provider = OpenTelemetry.meter_provider
      METRICS.each do |name, (type, _)|
        next unless type == :histogram

        boundaries = name.end_with?("_size") ? [ 1, 10, 25, 50, 100 ] : DURATION_BOUNDARIES
        provider.add_view(name, aggregation: OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram.new(
          boundaries: boundaries))
      end
      meter = provider.meter("hammerfall")
      @instruments = METRICS.each_with_object({}) do |(name, (type, _)), instruments|
        instruments[name] = case type
        when :counter then meter.create_counter(name, unit: "1")
        when :gauge then meter.create_gauge(name, unit: name.end_with?("_age") ? "s" : nil)
        else meter.create_histogram(name, unit: name.end_with?("_size") ? "1" : "s")
        end
      end
      @enabled = true
    rescue StandardError => error
      @enabled = false
      warn("observability initialization disabled error_class=#{error.class}")
    end

    def trace(name, attributes: {}, kind: :internal)
      return yield unless enabled?

      entered = false
      completed = false
      result = nil
      begin
        OpenTelemetry.tracer_provider.tracer("hammerfall").in_span(name,
          attributes: safe_span_attributes(attributes), kind: kind, record_exception: false) do
          entered = true
          result = yield
          completed = true
          result
        end
        result
      rescue StandardError
        return result if completed
        raise if entered

        yield
      end
    end

    def with_context(context)
      return yield unless enabled?

      entered = false
      completed = false
      result = nil
      begin
        OpenTelemetry::Context.with_current(context) do
          entered = true
          result = yield
          completed = true
          result
        end
        result
      rescue StandardError
        return result if completed
        raise if entered

        yield
      end
    end

    def counter(name, attributes: {})
      emit(name, 1, attributes)
    end

    def histogram(name, value, attributes: {})
      emit(name, value, attributes)
    end

    def gauge(name, value, attributes: {})
      emit(name, value, attributes)
    end

    # Only W3C trace metadata crosses durable or transport boundaries.
    def carrier
      return {} unless enabled?

      result = {}
      OpenTelemetry.propagation.inject(result)
      parent = result["traceparent"]
      return {} unless parent.is_a?(String) && parent.match?(/\A00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}\z/)

      state = result["tracestate"]
      state = nil unless state.is_a?(String) && state.bytesize <= 512
      { "traceparent" => parent, "tracestate" => state }.compact
    rescue StandardError
      {}
    end

    def extracted_context(carrier)
      return nil unless enabled? && carrier.is_a?(Hash)

      safe = carrier.slice("traceparent", "tracestate")
      return nil unless safe["traceparent"].is_a?(String) && safe["traceparent"].bytesize <= 55 &&
        (!safe.key?("tracestate") || (safe["tracestate"].is_a?(String) && safe["tracestate"].bytesize <= 512))

      OpenTelemetry.propagation.extract(safe, context: OpenTelemetry::Context::ROOT)
    rescue StandardError
      nil
    end

    def with_carrier(carrier)
      context = extracted_context(carrier)
      context ? with_context(context) { yield } : yield
    end

    # Broker high watermark minus the next committed offset. Throttled per
    # partition and capped at 100 ms; failure never participates in commits.
    def kafka_lag(consumer, message, group, last_checked)
      return unless enabled? && consumer.respond_to?(:query_watermark_offsets)

      partition = message.partition
      now = monotonic
      return if now - last_checked.fetch(partition, 0) < 30

      last_checked[partition] = now
      _low, high = consumer.query_watermark_offsets(message.topic, partition, 100)
      gauge("hammerfall_kafka_consumer_lag", [ high - message.offset - 1, 0 ].max,
        attributes: { consumer_group: group, partition: partition })
    rescue StandardError
      nil
    end

    def sidekiq_queue_depth
      return unless enabled?

      require "sidekiq/api"
      gauge("hammerfall_sidekiq_queue_depth", Sidekiq::Queue.new("notifications").size,
        attributes: { queue: "notifications" })
    rescue StandardError
      nil
    end

    def websocket_lag(auction_id, revision)
      return unless enabled?

      occurred_at = OutboxEvent.where(auction_id: auction_id, public_revision: revision).pick(:occurred_at)
      histogram("hammerfall_websocket_server_broadcast_lag", [ Time.now.utc - occurred_at, 0 ].max) if occurred_at
    rescue StandardError
      nil
    end

    def lock_wait(operation)
      started = monotonic
      trace("hammerfall.auction.lock", attributes: { "hammerfall.operation" => operation }) { yield }
    ensure
      histogram("hammerfall_auction_lock_wait_duration", monotonic - started,
        attributes: { operation: operation }) if started
    end

    def log(level:, **fields)
      payload = { timestamp: Time.now.utc.iso8601(6), level: level.to_s,
        service: @service_name || SERVICE_NAMES.fetch(File.basename($PROGRAM_NAME), "hammerfall-api") }
      fields.each { |key, value| payload[key] = value if LOG_FIELDS.include?(key.to_s) && !value.nil? }
      if enabled?
        context = OpenTelemetry::Trace.current_span.context
        if context.valid?
          payload[:trace_id] = context.hex_trace_id
          payload[:span_id] = context.hex_span_id
        end
      end
      $stdout.write("#{JSON.generate(payload)}\n")
    rescue StandardError
      nil
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def route(path)
      return path if ROUTES.include?(path)
      return "/api/v1/auctions/:id" if path.match?(%r{\A/api/v1/auctions/\d+\z})
      if (match = path.match(%r{\A/api/v1/auctions/\d+/(public-state|maximum-bid|bids|schedule|activate|close|cancel)\z}))
        return "/api/v1/auctions/:id/#{match[1]}"
      end

      "other"
    rescue StandardError
      "other"
    end

    private

    def safe_span_attributes(attributes)
      attributes.each_with_object({}) do |(key, value), safe|
        next unless SPAN_FIELDS.include?(key.to_s)

        dimension = { "hammerfall.operation" => "operation", "hammerfall.event_type" => "event_type",
          "http.request.method" => "method", "http.route" => "route" }.fetch(key.to_s)
        safe[key.to_s] = normalize(dimension, value)
      end
    end

    def emit(name, value, attributes)
      return unless enabled?

      type, dimensions = METRICS.fetch(name)
      normalized = dimensions.to_h do |dimension|
        raw = attributes[dimension.to_sym] || attributes[dimension]
        [ dimension, normalize(dimension, raw) ]
      end
      instrument = @instruments.fetch(name)
      type == :counter ? instrument.add(value, attributes: normalized) : instrument.record(value, attributes: normalized)
    rescue StandardError
      nil
    end

    def normalize(dimension, value)
      text = value.to_s
      allowed = case dimension
      when "operation" then OPERATIONS
      when "result" then RESULTS
      when "reason" then REASONS
      when "event_type" then EVENT_TYPES
      when "route" then ROUTES
      when "method" then %w[GET POST PUT PATCH DELETE]
      when "status_class" then %w[2xx 3xx 4xx 5xx]
      when "channel" then CHANNELS
      when "consumer_group" then CONSUMER_GROUPS
      when "kind" then DRIFT_KINDS
      when "partition" then (0..31).map(&:to_s)
      when "queue" then QUEUES
      when "source" then PROJECTION_SOURCES
      end
      allowed.include?(text) ? text : "other"
    end
  end
end
