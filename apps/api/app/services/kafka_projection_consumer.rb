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
    event = KafkaEventCodec.decode(message.payload, key: message.key)
    result = @projection.apply_event(event)
    consumer.store_offset(message)
    consumer.commit(nil, false)
    @logger.info("kafka_projection_consumer event_id=#{event.fetch('event_id')} result=#{result} partition=#{message.partition} offset=#{message.offset}")
    result
  rescue KafkaEventCodec::InvalidEvent => error
    @logger.error("kafka_projection_consumer poison partition=#{message.partition} offset=#{message.offset} error=#{error.class}")
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
