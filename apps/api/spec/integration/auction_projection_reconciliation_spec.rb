require "rails_helper"

RSpec.describe "Auction projection reconciliation" do
  let(:redis) { RedisClient.config(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1).new_client }
  let(:projection) { AuctionPublicProjection.new(redis: redis) }
  let(:reconciler) { AuctionProjectionReconciler.new(projection: projection, logger: logger) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil) }
  let(:auction) { create_auction(state: "active") }
  let(:key) { "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}" }

  after do
    redis.call("DEL", key) if defined?(@auction_id)
    redis.close
  end

  before { @auction_id = auction.id }

  it "repairs a missing key from PostgreSQL, then treats a repeated check as healthy" do
    expect(reconciler.check(auction)).to eq(:repaired)
    expect(reconciler.check(auction)).to eq(:healthy)
    expect(projection.read(auction.id)).to include("public_revision" => auction.public_revision, "source" => "postgresql_seed")
  end

  it "repairs a valid lower revision and does not regress a later Kafka update" do
    old_event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    projection.apply_event(old_event)
    auction.place_bid!(bidder: User.create!(name: "Reconciliation bidder"), amount: 10_000)
    expect(reconciler.check(auction.reload)).to eq(:repaired)
    current = projection.read(auction.id)
    expect(current.dig("data", "current_price")).to eq(10_000)
    expect(projection.apply_event(old_event)).to eq(:stale)
    expect(reconciler.check(auction)).to eq(:healthy)
  end

  it "accepts equal revision and data regardless of projection source" do
    expect(projection.seed(auction)).to eq(:applied)
    before = redis.call("GET", key)
    2.times { expect(reconciler.check(auction)).to eq(:healthy) }
    expect(redis.call("GET", key)).to eq(before)
  end

  it "escalates equal-revision conflict without changing the key" do
    messages = []
    allow(logger).to receive(:info) { |message| messages << JSON.parse(message) }
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    event.fetch("data")["description"] = "Other public text"
    projection.apply_event(event)
    before = redis.call("GET", key)
    expect(reconciler.check(auction)).to eq(:operator_review)
    expect(redis.call("GET", key)).to eq(before)
    expect(messages).to include(include("auction_id" => auction.id, "result" => "operator_review", "drift" => "conflicting"))
    expect(JSON.generate(messages)).not_to match(/maximum_amount|priority_sequence|bid_origin|key_digest|request_fingerprint/)
  end

  it "escalates a key ahead of a fresh PostgreSQL row" do
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    event["aggregate_version"] = auction.public_revision + 1
    projection.apply_event(event)
    before = redis.call("GET", key)
    expect(reconciler.check(auction)).to eq(:operator_review)
    expect(redis.call("GET", key)).to eq(before)
    expect(auction.reload.public_revision).to be < projection.read(auction.id).fetch("public_revision")
  end

  it "does not overwrite a same-revision conflict arriving during repair" do
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    event.fetch("data")["description"] = "Race value"
    allow(projection).to receive(:seed).and_wrap_original do |original, row|
      projection.apply_event(event)
      original.call(row)
    end
    expect(reconciler.check(auction)).to eq(:repair_failed_review)
    expect(projection.read(auction.id).dig("data", "description")).to eq("Race value")
  end

  it "escalates malformed and digest-corrupt projections without replacing them" do
    redis.call("SET", key, "broken")
    expect(reconciler.check(auction)).to eq(:operator_review)
    expect(redis.call("GET", key)).to eq("broken")
    redis.call("DEL", key)
    projection.seed(auction)
    value = JSON.parse(redis.call("GET", key))
    value.fetch("data")["current_price"] += 1
    redis.call("SET", key, JSON.generate(value))
    expect(reconciler.check(auction)).to eq(:operator_review)
    expect(JSON.parse(redis.call("GET", key)).dig("data", "current_price")).to eq(value.dig("data", "current_price"))
  end

  it "escalates a semantically impossible projection even with a matching digest" do
    projection.seed(auction)
    value = JSON.parse(redis.call("GET", key))
    value.fetch("data")["current_price"] = value.dig("data", "starting_price") - 1
    value["data_digest"] = Digest::SHA256.hexdigest(JSON.generate(value.fetch("data").sort.to_h))
    raw = JSON.generate(value)
    redis.call("SET", key, raw)
    expect(reconciler.check(auction)).to eq(:operator_review)
    expect(redis.call("GET", key)).to eq(raw)
  end

  it "reports Redis outage without changing PostgreSQL" do
    broken = AuctionPublicProjection.new(redis: RedisClient.config(url: "redis://127.0.0.1:1/0", timeout: 0.1,
      reconnect_attempts: 0).new_client)
    expect { AuctionProjectionReconciler.new(projection: broken, logger: logger).check(auction) }
      .to raise_error(AuctionProjectionReconciler::ProjectionUnavailable)
    expect(auction.reload.status).to eq("active")
  ensure
    broken&.close
  end

  it "emits bounded batch counters and leaves authoritative state untouched" do
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << JSON.parse(message) }
    before = auction.reload.attributes
    2.times { AuctionProjectionReconciliationJob.new.perform(auction.id - 1, auction.id) }
    expect(auction.reload.attributes).to eq(before)
    metrics = messages.select { |entry| entry["event"] == "auction_projection_reconciliation_metrics" }
    expect(metrics.map { |entry| entry["auction_projection_drift_total"] }).to eq([ 1, 0 ])
    expect(metrics.map { |entry| entry["auction_projection_repair_total"] }).to eq([ 1, 0 ])
    expect(metrics.map { |entry| entry["healthy"] }).to eq([ 0, 1 ])
    expect(metrics.all? { |entry| entry.keys.grep(/auction_id/).empty? }).to be(true)
  end

  it "counts a repair conflict as a failure and an operator case" do
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    event.fetch("data")["description"] = "Concurrent conflicting value"
    allow(AuctionPublicProjection).to receive(:new).and_return(projection)
    allow(projection).to receive(:seed).and_wrap_original do |original, row|
      projection.apply_event(event)
      original.call(row)
    end
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << JSON.parse(message) }
    AuctionProjectionReconciliationJob.new.perform(auction.id - 1, auction.id)
    metrics = messages.find { |entry| entry["event"] == "auction_projection_reconciliation_metrics" }
    expect(metrics).to include("auction_projection_drift_total" => 1,
      "auction_projection_repair_attempt_total" => 1, "auction_projection_repair_failure_total" => 1,
      "operator_review" => 1)
  end
end
