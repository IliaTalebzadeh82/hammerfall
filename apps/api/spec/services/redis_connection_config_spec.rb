require "spec_helper"
require "tmpdir"
require "redis-client"
require_relative "../../app/services/redis_connection_config"

RSpec.describe RedisConnectionConfig do
  it "preserves the local Redis URL" do
    expect(described_class.build(env: { "REDIS_URL" => "redis://redis:6379/0" })).to eq(url: "redis://redis:6379/0")
  end

  it "fails closed for roles that do not use Redis" do
    expect(described_class.build(env: { "REDIS_CONNECTION_MODE" => "disabled" }))
      .to eq(url: "redis://127.0.0.1:1/0", connect_timeout: 0.1)
  end

  it "requires TLS and a readable CA in cloud mode" do
    Dir.mktmpdir do |dir|
      ca = File.join(dir, "ca.pem")
      File.write(ca, "test CA")
      env = { "REDIS_CONNECTION_MODE" => "tls", "REDIS_URL" => "rediss://redis.internal:6379/0",
        "REDIS_TLS_CA_FILE" => ca, "REDIS_AUTH_MODE" => "none" }
      config = described_class.build(env: env)
      expect(config[:ssl_params]).to include(ca_file: ca, verify_mode: OpenSSL::SSL::VERIFY_PEER)
      expect { RedisClient.config(**config) }.not_to raise_error
      expect { described_class.build(env: env.merge("REDIS_URL" => "redis://redis.internal:6379/0")) }.to raise_error(ArgumentError)
      expect { described_class.build(env: env.merge("REDIS_URL" => "rediss://user:private@redis.internal:6379/0")) }.to raise_error(ArgumentError)
      expect { described_class.build(env: env.merge("REDIS_TLS_CA_FILE" => "")) }.to raise_error(ArgumentError)
    end
  end

  it "reads AUTH from a mounted file and does not expose it in errors" do
    Dir.mktmpdir do |dir|
      ca = File.join(dir, "ca.pem")
      password = File.join(dir, "password")
      File.write(ca, "test CA")
      File.write(password, "private-password\n")
      env = { "REDIS_CONNECTION_MODE" => "tls", "REDIS_URL" => "rediss://redis.internal:6379/0",
        "REDIS_TLS_CA_FILE" => ca, "REDIS_AUTH_MODE" => "auth", "REDIS_PASSWORD_FILE" => password }
      expect(described_class.build(env: env)[:password]).to eq("private-password")
      expect { described_class.build(env: env.merge("REDIS_PASSWORD_FILE" => "missing-private-password")) }
        .to raise_error(ArgumentError, /REDIS_PASSWORD_FILE is required/)
    end
  end
end
