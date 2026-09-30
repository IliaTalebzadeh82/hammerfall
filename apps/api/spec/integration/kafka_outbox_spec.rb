require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Kafka domain outbox", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  def event_for(auction)
    OutboxEvent.where(auction_id: auction.id).order(:public_revision).last
  end

  def fake_producer
    producer = double("Kafka producer")
    allow(producer).to receive(:produce) { double(wait: Object.new) }
    producer
  end

  def acknowledge_setup_events(auction)
    OutboxEvent.where(auction_id: auction.id).update_all(kafka_published_at: Time.current)
  end

  it "commits a versioned public event with the command and excludes private data" do
    auction = active_auction
    before = auction.public_revision
    IdempotentBidding.call(key: "kafka-bid", actor_id: @bidder.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000)
    event = event_for(auction)
    expect(event).to have_attributes(public_revision: before + 1, domain_event_type: "auction.price_changed.v1",
      kafka_published_at: nil, kafka_attempts: 0)
    expect(event.kafka_envelope).to include(event_id: event.event_id, aggregate_id: auction.id,
      aggregate_version: auction.reload.public_revision, schema_version: 1)
    expect(event.domain_payload).to include("status" => "active", "current_price" => 10_000)
    expect(event.kafka_envelope[:data].keys).not_to include("maximum_amount", "priority_sequence", "origin", "key_digest", "request_fingerprint")
    expect(IdempotencyRecord.where(actor_id: @bidder.id).pick(:status)).to eq("completed")
    expect(KafkaEventCodec.decode(JSON.generate(event.kafka_envelope), key: auction.id.to_s)["event_id"]).to eq(event.event_id)
  end

  it "classifies public terms, lifecycle and closure snapshots without a winner invention" do
    auction = create_auction
    @auction_ids << auction.id
    auction.edit_draft!(title: "Updated public title")
    expect(event_for(auction).domain_event_type).to eq("auction.terms_changed.v1")
    expect(event_for(auction).domain_payload["title"]).to eq("Updated public title")
    auction.schedule!
    expect(event_for(auction).domain_event_type).to eq("auction.status_changed.v1")
    auction.activate!
    expect(event_for(auction).domain_event_type).to eq("auction.status_changed.v1")
    expire_fixture(auction).close!
    expect(event_for(auction).domain_event_type).to eq("auction.closed.v1")
    expect(event_for(auction).domain_payload).to include("status" => "closed", "winner_id" => nil)
  end

  it "classifies a deadline-only public change as an extension" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    prior_price = auction.reload.current_price
    auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
    expect(auction.reload.current_price).to eq(prior_price)
    expect(event_for(auction).domain_event_type).to eq("auction.extended.v1")
    expect(event_for(auction).domain_payload["ends_at"]).to eq(auction.ends_at.utc.iso8601(6))
  end

  it "rolls back Kafka intent with the public mutation and keeps private-only changes silent" do
    auction = active_auction
    before = auction.public_revision
    ApplicationRecord.transaction do
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expect(event_for(auction).public_revision).to eq(before + 1)
      raise ActiveRecord::Rollback
    end
    expect(auction.reload.public_revision).to eq(before)
    expect(OutboxEvent.where(auction_id: auction.id, public_revision: before + 1)).to be_empty
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    count = OutboxEvent.where(auction_id: auction.id).count
    auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
    expect(OutboxEvent.where(auction_id: auction.id).count).to eq(count)
  end

  it "acks only after the Kafka delivery handle succeeds and retries broker failure" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    producer = fake_producer
    allow(producer).to receive(:produce).and_raise(IOError, "broker down")
    publisher = KafkaOutboxPublisher.new(producer: producer)
    expect(publisher.run_once).to include(published: 0, failed: 1)
    expect(event.reload).to have_attributes(kafka_published_at: nil, kafka_attempts: 1, kafka_last_error: "IOError")
    expect(auction.reload.current_price).to eq(10_000)
    event.update!(kafka_next_attempt_at: 1.second.ago)
    allow(producer).to receive(:produce) { double(wait: Object.new) }
    expect(publisher.run_once).to include(published: 1, failed: 0)
    expect(event.reload.kafka_published_at).to be_present
  end

  it "does not acknowledge a queued message whose delivery report fails" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    producer = double("producer", produce: double("handle"))
    allow(producer.produce).to receive(:wait).and_raise(IOError, "delivery failed")
    expect(KafkaOutboxPublisher.new(producer: producer).run_once[:failed]).to eq(1)
    expect(event.reload.kafka_published_at).to be_nil
  end

  it "retries after a delivery/ack crash and sends the same event ID twice" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    producer = fake_producer
    publisher = KafkaOutboxPublisher.new(producer: producer)
    allow_any_instance_of(OutboxEvent).to receive(:update!).and_raise(IOError, "ack crash")
    expect { publisher.run_once }.to raise_error(IOError, "ack crash")
    expect(event.reload.kafka_published_at).to be_nil
    allow_any_instance_of(OutboxEvent).to receive(:update!).and_call_original
    expect(publisher.run_once[:published]).to eq(1)
    expect(producer).to have_received(:produce).twice.with(hash_including(key: auction.id.to_s,
      topic: KafkaOutboxPublisher::TOPIC))
  end

  it "rejects unsupported or private fields and keeps poison records uncommitted" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction).kafka_envelope.stringify_keys
    broker = double("consumer", commit: nil)
    message = Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(event.merge("schema_version" => 2)), auction.id.to_s, 0, 12)
    consumer = KafkaAuditConsumer.new(consumer: broker)
    expect { consumer.process(message) }.to raise_error(KafkaEventCodec::InvalidEvent)
    expect(ConsumedKafkaEvent.where(auction_id: auction.id)).to be_empty
    expect(broker).not_to have_received(:commit)
    expect { KafkaEventCodec.decode(JSON.generate(event.merge("data" => event.fetch("data").merge("maximum_amount" => 99))), key: auction.id.to_s) }.to raise_error(KafkaEventCodec::InvalidEvent)
  end

  it "commits audit and receipt once, then offset; replay and stale arrival are harmless" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    first = event_for(auction)
    auction.place_bid!(bidder: @bidder, amount: 11_000)
    second = event_for(auction)
    broker = double("consumer", store_offset: nil, commit: nil)
    consumer = KafkaAuditConsumer.new(consumer: broker)
    make_message = ->(event, offset) { Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(event.kafka_envelope), auction.id.to_s, 0, offset) }
    expect(consumer.process(make_message.call(second, 1))).to eq(:first)
    expect(consumer.process(make_message.call(first, 2))).to eq(:stale)
    expect(consumer.process(make_message.call(first, 3))).to eq(:duplicate)
    altered = first.kafka_envelope.merge(data: first.domain_payload.merge("current_price" => 999_999))
    conflicting = Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(altered), auction.id.to_s, 0, 4)
    expect { consumer.process(conflicting) }.to raise_error(KafkaEventCodec::InvalidEvent, /reused/)
    expect(KafkaAuditEntry.where(auction_id: auction.id).pluck(:arrival_order)).to contain_exactly("first", "stale")
    expect(ConsumedKafkaEvent.where(auction_id: auction.id).count).to eq(2)
    expect(broker).to have_received(:commit).exactly(3).times
  end

  it "does not store an offset if the database side effect rolls back" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    broker = double("consumer", store_offset: nil, commit: nil)
    consumer = KafkaAuditConsumer.new(consumer: broker)
    message = Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(event.kafka_envelope), auction.id.to_s, 0, 1)
    allow(KafkaAuditEntry).to receive(:create!).and_raise(IOError, "audit disk failure")
    expect { consumer.process(message) }.to raise_error(IOError, "audit disk failure")
    expect(ConsumedKafkaEvent.where(auction_id: auction.id)).to be_empty
    expect(broker).not_to have_received(:store_offset)
    expect(broker).not_to have_received(:commit)
  end

  it "keeps one receipt and effect when duplicate group members race" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    envelope = event_for(auction).kafka_envelope
    payload = JSON.generate(envelope)
    event = KafkaEventCodec.decode(payload, key: auction.id.to_s)
    digest = Digest::SHA256.hexdigest(payload)
    entered = Queue.new
    release = Queue.new
    first_pid = Queue.new
    second_pid = Queue.new
    allow(KafkaAuditEntry).to receive(:create!).and_wrap_original do |original, **attributes|
      entered << true
      release.pop
      original.call(**attributes)
    end
    first = worker do |connection|
      first_pid << connection.select_value("SELECT pg_backend_pid()")
      ConsumedKafkaEvent.record!(consumer_name: KafkaAuditConsumer::GROUP, event: event, payload_digest: digest)
    end
    take(entered)
    second = worker do |connection|
      second_pid << connection.select_value("SELECT pg_backend_pid()")
      ConsumedKafkaEvent.record!(consumer_name: KafkaAuditConsumer::GROUP, event: event, payload_digest: digest)
    end
    holder = take(first_pid)
    waiter = take(second_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until ApplicationRecord.connection.select_value("SELECT #{holder.to_i} = ANY(pg_blocking_pids(#{waiter.to_i}))")
      raise "Duplicate consumer never waited on receipt" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.005
    end
    release << true
    expect(result(first)).to eq(:first)
    expect(result(second)).to eq(:duplicate)
    expect(ConsumedKafkaEvent.where(event_id: event.fetch("event_id")).count).to eq(1)
    expect(KafkaAuditEntry.where(event_id: event.fetch("event_id")).count).to eq(1)
  end

  it "uses PostgreSQL time for Kafka retry and acknowledgment despite host clock skew" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    db_before = ApplicationRecord.connection.select_value("SELECT clock_timestamp()")
    allow(Time).to receive(:current).and_return(db_before + 1.year)
    producer = fake_producer
    allow(producer).to receive(:produce).and_raise(IOError, "broker down")
    publisher = KafkaOutboxPublisher.new(producer: producer)
    expect(publisher.run_once[:failed]).to eq(1)
    expect(event.reload.kafka_next_attempt_at).to be_between(db_before, db_before + 30.seconds)
    expect(publisher.backlog_metrics[:oldest_age_seconds]).to be < 60
    event.update!(kafka_next_attempt_at: ApplicationRecord.connection.select_value("SELECT clock_timestamp()") - 1.second)
    allow(producer).to receive(:produce) { double(wait: Object.new) }
    expect(publisher.run_once[:published]).to eq(1)
    expect(event.reload.kafka_published_at).to be_between(db_before, ApplicationRecord.connection.select_value("SELECT clock_timestamp()"))
  end

  it "excludes the same claimed row but lets another Kafka publisher advance a different row" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    first_revision = auction.reload.public_revision
    auction.place_bid!(bidder: @bidder, amount: 11_000)
    claimed = Queue.new
    release = Queue.new
    producer = double("producer")
    allow(producer).to receive(:produce) do |**options|
      if JSON.parse(options.fetch(:payload)).fetch("aggregate_version") == first_revision
        claimed << true
        release.pop
      end
      double(wait: Object.new)
    end
    first = worker { KafkaOutboxPublisher.new(producer: producer, batch_size: 1).run_once }
    take(claimed)
    expect(result(worker { KafkaOutboxPublisher.new(producer: producer, batch_size: 1).run_once })[:published]).to eq(1)
    expect(OutboxEvent.where(auction_id: auction.id).where.not(kafka_published_at: nil).pluck(:public_revision)).to include(first_revision + 1)
    expect(event_for(auction).reload.kafka_published_at).to be_present
    release << true
    expect(result(first)[:published]).to eq(1)
    expect(OutboxEvent.where(auction_id: auction.id, public_revision: first_revision).pick(:kafka_published_at)).to be_present
  end
end
