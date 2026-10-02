# Deliberately redeliver one already-published immutable outbox event to Kafka.
require "json"

event = OutboxEvent.find_by!(event_id: ENV.fetch("CHAOS_EVENT_ID"))
raise "event was never broker-acknowledged" unless event.kafka_published_at

producer = Rdkafka::Config.new(
  "bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"),
  "acks": "all", "enable.idempotence": true, "message.timeout.ms": 5000
).producer
begin
  receipt = producer.produce(topic: KafkaOutboxPublisher::TOPIC,
    key: event.auction_id.to_s, payload: JSON.generate(event.kafka_envelope)).wait
  raise "missing broker receipt" unless receipt
  puts JSON.generate(event_id: event.event_id, auction_id: event.auction_id,
    public_revision: event.public_revision, broker_acknowledged: true)
ensure
  producer.close
end
