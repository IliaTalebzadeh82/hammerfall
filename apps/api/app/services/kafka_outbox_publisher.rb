class KafkaOutboxPublisher
  class DeliveryFailed < StandardError; end

  TOPIC = "hammerfall.auction-events.v1"

  def initialize(producer: nil, interval: ENV.fetch("KAFKA_PUBLISH_INTERVAL", "1"),
    batch_size: ENV.fetch("KAFKA_PUBLISH_BATCH_SIZE", "100"), logger: Rails.logger)
    @producer = producer
    @owns_producer = producer.nil?
    @interval = Float(interval)
    @batch_size = Integer(batch_size)
    raise ArgumentError, "interval must be positive" unless @interval.finite? && @interval.positive?
    raise ArgumentError, "batch size must be between 1 and 1000" unless (1..1000).cover?(@batch_size)
    @logger = logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run_once
    published = 0
    failed = 0
    @batch_size.times do
      break if @stopping
      found = false
      OutboxEvent.transaction do
        event = OutboxEvent.kafka_due.order(:kafka_next_attempt_at, :id).lock("FOR UPDATE SKIP LOCKED").first
        if event
          found = true
          started = Observability.monotonic
          Observability.counter("hammerfall_outbox_publish_attempts", attributes: { channel: "kafka" })
          Observability.counter("hammerfall_outbox_retry_attempts", attributes: { channel: "kafka" }) if event.kafka_attempts.positive?
          begin
            receipt = Observability.with_carrier(event.trace_carrier) do
              Observability.trace("hammerfall.kafka.publish", kind: :producer,
                attributes: { "hammerfall.event_type" => event.domain_event_type }) do
                producer.produce(topic: TOPIC, key: event.auction_id.to_s,
                  payload: JSON.generate(event.kafka_envelope), headers: Observability.carrier).wait
              end
            end
            raise DeliveryFailed, "missing delivery report" unless receipt
          rescue StandardError => error
            Observability.counter("hammerfall_outbox_publish_failures", attributes: { channel: "kafka" })
            attempts = event.kafka_attempts + 1
            delay = [ 2**[ attempts, 8 ].min, 300 ].min
            database_now = OutboxEvent.connection.select_value("SELECT clock_timestamp()")
            event.update!(kafka_attempts: attempts, kafka_last_error: error.class.name.to_s.first(255),
              kafka_next_attempt_at: database_now + delay)
            @logger.warn("kafka_outbox_publisher delivery_failed event_id=#{event.event_id} error=#{error.class}")
            Observability.log(level: :warn, component: "kafka_outbox_publisher", operation: "publish",
              result: "failed", error_class: error.class.name, event_type: event.domain_event_type,
              event_id: event.event_id, retry_count: attempts, public_revision: event.public_revision)
            failed += 1
          else
            # A crash here leaves the row pending and can produce a duplicate.
            database_now = OutboxEvent.connection.select_value("SELECT clock_timestamp()")
            event.update!(kafka_published_at: database_now, kafka_attempts: event.kafka_attempts + 1, kafka_last_error: nil)
            Observability.log(level: :info, component: "kafka_outbox_publisher", operation: "publish",
              result: "succeeded", event_type: event.domain_event_type, event_id: event.event_id,
              retry_count: event.kafka_attempts, public_revision: event.public_revision)
            published += 1
          ensure
            Observability.histogram("hammerfall_outbox_publish_duration", Observability.monotonic - started,
              attributes: { channel: "kafka" })
          end
        end
      end
      break unless found
    end
    metrics = backlog_metrics
    Observability.gauge("hammerfall_outbox_pending_events", metrics[:backlog], attributes: { channel: "kafka" })
    Observability.gauge("hammerfall_outbox_oldest_event_age", metrics[:oldest_age_seconds], attributes: { channel: "kafka" })
    @logger.info("kafka_outbox_publisher published=#{published} failed=#{failed} backlog=#{metrics[:backlog]} due=#{metrics[:due]} retries=#{metrics[:retries]} oldest_age_seconds=#{metrics[:oldest_age_seconds]}")
    { published: published, failed: failed, **metrics }
  end

  def backlog_metrics
    pending = OutboxEvent.kafka_pending
    oldest = pending.minimum(:occurred_at)
    now = OutboxEvent.connection.select_value("SELECT clock_timestamp()") if oldest
    { backlog: pending.count, due: OutboxEvent.kafka_due.count, retries: pending.where("kafka_attempts > 0").count,
      oldest_age_seconds: oldest ? [ (now - oldest).to_i, 0 ].max : 0 }
  end

  def run(once: false)
    loop do
      break if @stopping
      begin
        result = ApplicationRecord.connection_pool.with_connection { run_once }
        raise DeliveryFailed, "#{result[:failed]} delivery attempts failed" if once && result[:failed].positive?
      rescue StandardError => error
        @logger.warn("kafka_outbox_publisher cycle_failed error=#{error.class}")
        raise if once
      end
      break if once || @stopping
      sleep(@interval)
    end
  ensure
    @producer&.close if @owns_producer
  end

  private

  def producer
    @producer ||= Rdkafka::Config.new(
      "bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "127.0.0.1:9092"),
      "acks": "all", "enable.idempotence": true, "message.timeout.ms": 5000,
      "socket.timeout.ms": 3000
    ).producer
  end
end
