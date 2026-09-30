class AddKafkaReceiptDigest < ActiveRecord::Migration[8.1]
  def change
    add_column :consumed_kafka_events, :payload_digest, :string, limit: 64
    add_check_constraint :consumed_kafka_events,
      "payload_digest IS NULL OR payload_digest ~ '^[0-9a-f]{64}$'",
      name: "consumed_kafka_events_payload_digest"
  end
end
