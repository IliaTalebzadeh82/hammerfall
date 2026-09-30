require "rails_helper"
require "securerandom"
require_relative "../support/committed_auction_context"

RSpec.describe "Live auction projection reconciliation" do
  KAFKA_TEST_TOPIC = "hammerfall.phase12.verify"
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  before do |example|
    if example.metadata[:live_kafka] && ENV["PHASE12_LIVE_KAFKA"] != "1"
      skip "set PHASE12_LIVE_KAFKA=1 and create #{KAFKA_TEST_TOPIC} for the live broker race"
    end
  end

  let(:redis) { RedisClient.config(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1).new_client }

  after do
    @auction_ids.each { |id| redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{id}") }
    redis.close
  end

  def event_for(auction)
    OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope
  end

  def deliver_through_kafka(event)
    broker = ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "127.0.0.1:29092")
    consumer = Rdkafka::Config.new("bootstrap.servers": broker,
      "group.id": "hammerfall.phase12.#{SecureRandom.hex(8)}", "auto.offset.reset": "latest",
      "enable.auto.commit": false, "enable.auto.offset.store": false).consumer
    producer = Rdkafka::Config.new("bootstrap.servers": broker, "acks": "all").producer
    consumer.subscribe(KAFKA_TEST_TOPIC)
    consumer.poll(1000) # Establish assignment before publishing into a new group's latest offset.
    producer.produce(topic: KAFKA_TEST_TOPIC, key: event.fetch(:aggregate_id).to_s,
      payload: JSON.generate(event)).wait
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      message = consumer.poll(500)
      if message && KafkaEventCodec.decode(message.payload, key: message.key).fetch("event_id") == event.fetch(:event_id)
        yield consumer, message
        break
      end
      raise "Kafka projection event not delivered" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end
  ensure
    consumer&.close
    producer&.close
  end

  it "does not regress a newer Kafka projection delivered between comparison and repair", :live_kafka do
    auction = active_auction
    old_snapshot = Auction.find(auction.id)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    projection = AuctionPublicProjection.new(redis: redis)

    deliver_through_kafka(event) do |consumer, message|
      allow(projection).to receive(:seed).and_wrap_original do |original, row|
        expect(KafkaProjectionConsumer.new(consumer: consumer, projection: projection).process(message)).to eq(:applied)
        original.call(row)
      end
      expect(AuctionProjectionReconciler.new(projection: projection).check(old_snapshot)).to eq(:raced)
    end
    expect(projection.read(auction.id)).to include("public_revision" => auction.reload.public_revision, "source" => "kafka")
    expect(AuctionProjectionReconciler.new(projection: projection).check(auction)).to eq(:healthy)
  end

  it "converges when repair wins before a later Kafka delivery", :live_kafka do
    auction = active_auction
    old_snapshot = Auction.find(auction.id)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    projection = AuctionPublicProjection.new(redis: redis)
    expect(AuctionProjectionReconciler.new(projection: projection).check(old_snapshot)).to eq(:repaired)
    expect(projection.read(auction.id).fetch("public_revision")).to eq(old_snapshot.public_revision)

    deliver_through_kafka(event_for(auction)) do |consumer, message|
      expect(KafkaProjectionConsumer.new(consumer: consumer, projection: projection).process(message)).to eq(:applied)
    end
    expect(AuctionProjectionReconciler.new(projection: projection).check(auction.reload)).to eq(:healthy)
  end

  it "allows two reconcilers to repair the same missing key without corruption" do
    auction = active_auction
    entered = Queue.new
    release = Queue.new
    threads = Array.new(2) do
      Thread.new do
        local = AuctionPublicProjection.new
        local.define_singleton_method(:seed) do |row|
          entered << true
          release.pop
          AuctionPublicProjection.instance_method(:seed).bind_call(self, row)
        end
        begin
          AuctionProjectionReconciler.new(projection: local).check(Auction.find(auction.id))
        ensure
          local.close
        end
      end
    end
    @threads.concat(threads)
    2.times { take(entered) }
    2.times { release << true }
    expect(threads.map { |thread| result(thread) }).to eq([ :repaired, :repaired ])
    projection = AuctionPublicProjection.new(redis: redis)
    expect(projection.read(auction.id).fetch("public_revision")).to eq(auction.public_revision)
    expect(AuctionProjectionReconciler.new(projection: projection).check(auction)).to eq(:healthy)
  ensure
    2.times { release << true } if release
  end

  it "retries safely after a crash following the Redis write" do
    auction = active_auction
    projection = AuctionPublicProjection.new(redis: redis)
    allow(projection).to receive(:seed).and_wrap_original do |original, row|
      original.call(row)
      raise IOError, "process died after repair"
    end
    expect { AuctionProjectionReconciler.new(projection: projection).check(auction) }.to raise_error(IOError)
    expect(projection.read(auction.id).fetch("public_revision")).to eq(auction.public_revision)
    fresh_projection = AuctionPublicProjection.new
    expect(AuctionProjectionReconciler.new(projection: fresh_projection).check(auction)).to eq(:healthy)
  ensure
    fresh_projection&.close
  end

  it "scans exactly one 100-row page and continues under its original ceiling" do
    auctions = Array.new(AuctionProjectionReconciliationJob::BATCH_SIZE + 1) { active_auction }
    first, last = auctions.first, auctions.last
    Sidekiq.testing!(:fake) do
      AuctionProjectionReconciliationJob.clear
      AuctionProjectionReconciliationJob.new.perform(first.id - 1, last.id)
      expect(AuctionProjectionReconciliationJob.jobs.length).to eq(1)
      expect(AuctionProjectionReconciliationJob.jobs.first.fetch("args")).to eq([ auctions[-2].id, last.id ])
      expect(redis.call("EXISTS", "#{AuctionPublicProjection::KEY_PREFIX}#{last.id}")).to eq(0)
      expect(redis.call("EXISTS", "#{AuctionPublicProjection::KEY_PREFIX}#{auctions[-2].id}")).to eq(1)
      AuctionProjectionReconciliationJob.new.perform(auctions[-2].id, last.id)
      expect(redis.call("EXISTS", "#{AuctionPublicProjection::KEY_PREFIX}#{last.id}")).to eq(1)
      expect(AuctionProjectionReconciliationJob.jobs.length).to eq(1)
    ensure
      AuctionProjectionReconciliationJob.clear
    end
  end
end
