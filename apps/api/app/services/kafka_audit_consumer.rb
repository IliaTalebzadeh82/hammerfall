require "digest"

class KafkaAuditConsumer
  GROUP = "hammerfall.audit.v1"

  def initialize(consumer: nil, logger: Rails.logger)
    @consumer = consumer
    @owns_consumer = consumer.nil?
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
  end

  def process(message)
    event = KafkaEventCodec.decode(message.payload, key: message.key)
    result = ConsumedKafkaEvent.record!(consumer_name: GROUP, event: event,
      payload_digest: Digest::SHA256.hexdigest(message.payload))
    # Offset follows the committed PostgreSQL side effect and receipt.
    consumer.store_offset(message)
    consumer.commit(nil, false)
    @logger.info("kafka_audit_consumer event_id=#{event.fetch('event_id')} result=#{result} partition=#{message.partition} offset=#{message.offset}")
    result
  rescue KafkaEventCodec::InvalidEvent => error
    @logger.error("kafka_audit_consumer poison partition=#{message.partition} offset=#{message.offset} error=#{error.class}")
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
