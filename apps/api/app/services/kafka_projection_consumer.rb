class KafkaProjectionConsumer
  GROUP = "hammerfall.projection.v1"

  def initialize(consumer: nil, projection: nil, logger: Rails.logger)
    @consumer = consumer
    @owns_consumer = consumer.nil?
    @projection = projection || AuctionPublicProjection.new
    @owns_projection = projection.nil?
    @logger = logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run(once: false)
    consumer.subscribe(KafkaOutboxPublisher::TOPIC)
    loop do
      break if @stopping
      message = consumer.poll(once ? 2000 : 1000)
      break if once && !message
      next unless message
      process(message)
      break if once
    end
  ensure
    @consumer&.close if @owns_consumer
    @projection.close if @owns_projection
  end

  def process(message)
    Observability.with_carrier(message.respond_to?(:headers) ? message.headers : nil) do
      Observability.trace("hammerfall.kafka.consume", kind: :consumer) do
        event = Observability.trace("hammerfall.kafka.validate") { KafkaEventCodec.decode(message.payload, key: message.key) }
        result = Observability.trace("hammerfall.projection.update") { @projection.apply_event(event) }
        Observability.trace("hammerfall.kafka.commit") do
          consumer.store_offset(message)
          consumer.commit(nil, false)
        end
        Observability.kafka_lag(consumer, message, GROUP, (@last_lag_query ||= {}))
        Observability.counter("hammerfall_kafka_consumed", attributes: { consumer_group: GROUP, result: result })
        Observability.log(level: :info, component: "kafka_projection_consumer", operation: "consume",
          result: result, event_type: event.fetch("event_type"), event_id: event.fetch("event_id"),
          consumer_group: GROUP, partition: message.partition, offset: message.offset,
          public_revision: event.fetch("aggregate_version"))
        result
      end
    end
  rescue KafkaEventCodec::InvalidEvent => error
    Observability.log(level: :error, component: "kafka_projection_consumer", operation: "consume",
      result: "poison", error_class: error.class.name, consumer_group: GROUP,
      partition: message.partition, offset: message.offset)
    @logger.error("kafka_projection_consumer poison partition=#{message.partition} offset=#{message.offset} error=#{error.class}")
    raise
  rescue RedisClient::CommandError => error
    result = error.message.include?("projection revision conflict") ? "conflict" : "redis_failure"
    Observability.log(level: :error, component: "kafka_projection_consumer", operation: "consume",
      result: result, error_class: error.class.name, consumer_group: GROUP,
      partition: message.partition, offset: message.offset)
    raise
  rescue RedisClient::Error => error
    Observability.log(level: :error, component: "kafka_projection_consumer", operation: "consume",
      result: "redis_failure", error_class: error.class.name, consumer_group: GROUP,
      partition: message.partition, offset: message.offset)
    raise
  rescue StandardError => error
    Observability.log(level: :error, component: "kafka_projection_consumer", operation: "consume",
      result: "failed", error_class: error.class.name, consumer_group: GROUP,
      partition: message.partition, offset: message.offset)
    raise
  end

  private

  def consumer
    @consumer ||= Rdkafka::Config.new(
      "bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "127.0.0.1:9092"),
      "group.id": GROUP, "auto.offset.reset": "earliest", "enable.auto.commit": false,
      "enable.auto.offset.store": false
    ).consumer
  end
end
