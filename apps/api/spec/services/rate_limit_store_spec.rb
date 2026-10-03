require "rails_helper"

RSpec.describe RateLimitStore do
  before { described_class.reset_test! }

  it "shares a Redis quota across independent store instances" do
    first = described_class.new(:bid)
    second = described_class.new(:bid)
    key = "distributed-spec-#{SecureRandom.hex(8)}"
    expect(first.increment(key, 1, expires_in: 30.seconds)).to eq(1)
    expect(second.increment(key, 1, expires_in: 30.seconds)).to eq(2)
  end

  it "fails closed for authentication and Cable when Redis is unavailable" do
    failed = double("failed Redis")
    allow(failed).to receive(:increment).and_raise(Redis::CannotConnectError)
    %i[auth cable].each do |kind|
      store = described_class.new(kind, redis: failed)
      expect { store.increment("outage", 1, expires_in: 1.minute) }.to raise_error(described_class::BackendUnavailable)
    end
  end

  it "uses bounded local counters for bidding and privileged actions during outage" do
    failed = double("failed Redis")
    allow(failed).to receive(:increment).and_raise(Redis::CannotConnectError)
    %i[bid privileged].each do |kind|
      store = described_class.new(kind, redis: failed)
      expect(store.increment("outage", 1, expires_in: 1.minute)).to eq(2)
      expect(store.increment("outage", 1, expires_in: 1.minute)).to eq(4)
    end
  end
end
