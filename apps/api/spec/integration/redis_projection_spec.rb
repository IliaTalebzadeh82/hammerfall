require "rails_helper"

RSpec.describe "Redis public auction projection", type: :request do
  let(:redis) { RedisClient.config(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1).new_client }
  let(:projection) { AuctionPublicProjection.new(redis: redis) }

  after do
    @auction_ids&.each { |id| redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{id}") }
    redis.close
  end

  def tracked_auction
    auction = create_auction(state: "active")
    (@auction_ids ||= []) << auction.id
    auction
  end

  def event_for(auction)
    OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
  end

  def message(event, offset)
    Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(event), event.fetch("aggregate_id").to_s, 0, offset)
  end

  it "stores a public snapshot with version and freshness, and serves an explicit eventual read" do
    auction = tracked_auction
    auction.place_bid!(bidder: User.create!(name: "Projection bidder"), amount: 10_000)
    event = event_for(auction)
    broker = double("broker", store_offset: nil, commit: nil)
    expect(KafkaProjectionConsumer.new(consumer: broker, projection: projection).process(message(event, 1))).to eq(:applied)
    state = projection.read(auction.id)
    expect(state).to include("auction_id" => auction.id, "public_revision" => auction.reload.public_revision,
      "event_id" => event.fetch("event_id"), "source" => "kafka")
    expect(state.fetch("projected_at_ms")).to be > 0
    expect(state.fetch("data").keys).to match_array(KafkaEventCodec::DATA_KEYS)
    expect(JSON.generate(state)).not_to match(/maximum_amount|priority_sequence|key_digest|request_fingerprint|bid_origin/)
    get "/api/v1/auctions/#{auction.id}/public-state"
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("current_price" => 10_000, "public_revision" => auction.public_revision)
    expect(json.fetch("meta")).to include("source" => "redis", "event_occurred_at" => event.fetch("occurred_at"))
    expect(json.dig("meta", "age_seconds")).to be >= 0
    expect(broker).to have_received(:commit).once
  end

  it "ignores duplicate and older revisions, including concurrent arrivals" do
    auction = tracked_auction
    first = event_for(auction)
    auction.place_bid!(bidder: User.create!(name: "Other bidder"), amount: 10_000)
    second = event_for(auction)
    results = Queue.new
    threads = [ first, second ].map do |event|
      Thread.new do
        local_projection = AuctionPublicProjection.new
        begin
          results << local_projection.apply_event(event)
        ensure
          local_projection.close
        end
      end
    end
    threads.each(&:join)
    expect([ results.pop, results.pop ]).to satisfy { |values| values.include?(:applied) && (values - %i[applied stale]).empty? }
    expect(projection.read(auction.id).fetch("public_revision")).to eq(second.fetch("aggregate_version"))
    expect(projection.apply_event(second)).to eq(:duplicate)
    expect(projection.apply_event(first)).to eq(:stale)
    expect(projection.read(auction.id).fetch("data").fetch("current_price")).to eq(10_000)
  end

  it "blocks a same-revision conflict and never commits its offset" do
    auction = tracked_auction
    event = event_for(auction)
    broker = double("broker", store_offset: nil, commit: nil)
    consumer = KafkaProjectionConsumer.new(consumer: broker, projection: projection)
    expect(consumer.process(message(event, 1))).to eq(:applied)
    changed = event.deep_dup
    changed.fetch("data")["current_price"] += 1
    expect { consumer.process(message(changed, 2)) }.to raise_error(RedisClient::CommandError, /revision conflict/)
    expect(broker).to have_received(:commit).once
    expect(projection.read(auction.id).fetch("data").fetch("current_price")).to eq(event.fetch("data").fetch("current_price"))
  end

  it "shows stale projection age and current PostgreSQL truth, then seeds after Redis loss" do
    auction = tracked_auction
    projection.apply_event(event_for(auction))
    auction.place_bid!(bidder: User.create!(name: "New bidder"), amount: 10_000)
    get "/api/v1/auctions/#{auction.id}/public-state"
    expect(json.fetch("data")).to include("current_price" => auction.starting_price,
      "public_revision" => auction.public_revision - 1)
    expect(json.dig("meta", "source")).to eq("redis")
    get "/api/v1/auctions/#{auction.id}"
    expect(json.fetch("data")).to include("current_price" => 10_000, "public_revision" => auction.reload.public_revision)
    redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}")
    get "/api/v1/auctions/#{auction.id}/public-state"
    expect(json.fetch("data")).to include("current_price" => 10_000)
    expect(json.dig("meta", "source")).to eq("postgresql")
    expect(projection.seed(auction.reload)).to eq(:applied)
    expect(projection.apply_event(event_for(auction))).to eq(:duplicate)
    expect(projection.read(auction.id)).to include("public_revision" => auction.public_revision, "source" => "postgresql_seed")
  end

  it "keeps a private maximum out of the PostgreSQL rebuild snapshot" do
    auction = tracked_auction
    bidder = User.create!(name: "Private maximum bidder")
    auction.place_bid!(bidder: bidder, amount: 10_000)
    auction.set_maximum!(bidder: bidder, maximum_amount: 20_000)
    expect(projection.seed(auction.reload)).to eq(:applied)
    raw = redis.call("GET", "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}")
    expect(raw).not_to include("maximum_amount", "priority_sequence", "20000")
    expect(projection.read(auction.id).fetch("data").keys).to match_array(KafkaEventCodec::DATA_KEYS)
  end

  it "does not commit a poison or failed Redis write" do
    auction = tracked_auction
    event = event_for(auction)
    broker = double("broker", store_offset: nil, commit: nil)
    consumer = KafkaProjectionConsumer.new(consumer: broker, projection: projection)
    expect { consumer.process(message(event.merge("schema_version" => 2), 1)) }.to raise_error(KafkaEventCodec::InvalidEvent)
    failed = AuctionPublicProjection.new(redis: RedisClient.config(url: "redis://127.0.0.1:1/0", timeout: 0.1, reconnect_attempts: 0).new_client)
    expect { KafkaProjectionConsumer.new(consumer: broker, projection: failed).process(message(event, 2)) }.to raise_error(RedisClient::Error)
    expect(broker).not_to have_received(:commit)
    expect(auction.reload.status).to eq("active")
  end

  it "replays safely after a crash between Redis write and offset commit" do
    auction = tracked_auction
    event = event_for(auction)
    broker = double("broker", store_offset: nil, commit: nil)
    allow(broker).to receive(:store_offset).and_raise(IOError, "consumer killed before offset")
    consumer = KafkaProjectionConsumer.new(consumer: broker, projection: projection)
    expect { consumer.process(message(event, 1)) }.to raise_error(IOError, /consumer killed/)
    expect(projection.read(auction.id).fetch("public_revision")).to eq(event.fetch("aggregate_version"))
    allow(broker).to receive(:store_offset).and_return(nil)
    expect(consumer.process(message(event, 1))).to eq(:duplicate)
    expect(broker).to have_received(:commit).once
  end

  it "falls back to PostgreSQL when Redis is unavailable without changing auction truth" do
    auction = tracked_auction
    allow(AuctionPublicProjection).to receive(:new).and_return(
      AuctionPublicProjection.new(redis: RedisClient.config(url: "redis://127.0.0.1:1/0", timeout: 0.1,
        reconnect_attempts: 0).new_client))
    get "/api/v1/auctions/#{auction.id}/public-state"
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("public_revision" => auction.public_revision, "status" => "active")
    expect(json.dig("meta", "source")).to eq("postgresql")
    expect(auction.reload.status).to eq("active")
  end
end
