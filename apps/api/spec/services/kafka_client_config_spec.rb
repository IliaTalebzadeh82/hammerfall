require "spec_helper"
require_relative "../../app/services/kafka_client_config"
require "rdkafka"

RSpec.describe KafkaClientConfig do
  it "preserves the local Compose bootstrap without cloud properties" do
    expect(described_class.build(env: { "KAFKA_BOOTSTRAP_SERVERS" => "kafka:9092" })).to eq(
      "bootstrap.servers": "kafka:9092")
  end

  it "builds Google's documented librdkafka OIDC configuration" do
    config = described_class.build(env: {
      "KAFKA_AUTH_MODE" => "google_oidc",
      "KAFKA_BOOTSTRAP_SERVERS" => "broker.private.example:9092",
      "KAFKA_OAUTH_TOKEN_ENDPOINT" => "http://127.0.0.1:14293"
    })

    expect(config).to include("security.protocol": "SASL_SSL", "enable.ssl.certificate.verification": true,
      "ssl.endpoint.identification.algorithm": "https", "sasl.mechanisms": "OAUTHBEARER",
      "sasl.oauthbearer.method": "oidc", "sasl.oauthbearer.token.endpoint.url": "http://127.0.0.1:14293")
    expect(config.keys).not_to include("sasl.username", "sasl.password", "ssl.key.location")
    expect { Rdkafka::Config.new(config) }.not_to raise_error
  end

  it "fails closed on incomplete or unsupported cloud configuration without echoing values" do
    [
      { "KAFKA_AUTH_MODE" => "google_oidc", "KAFKA_OAUTH_TOKEN_ENDPOINT" => "http://127.0.0.1:14293" },
      { "KAFKA_AUTH_MODE" => "google_oidc", "KAFKA_BOOTSTRAP_SERVERS" => "broker:9092" },
      { "KAFKA_AUTH_MODE" => "google_oidc", "KAFKA_BOOTSTRAP_SERVERS" => "broker:9092",
        "KAFKA_OAUTH_TOKEN_ENDPOINT" => "http://attacker.invalid/private-token" },
      { "KAFKA_AUTH_MODE" => "unexpected-secret-value" }
    ].each do |env|
      expect { described_class.build(env: env) }.to raise_error(ArgumentError) do |error|
        expect(error.message).not_to include("unexpected-secret-value", "attacker.invalid")
      end
    end
  end
end
