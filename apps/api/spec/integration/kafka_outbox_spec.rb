require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Kafka domain outbox", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  before do |example|
    skip "set PHASE12_5_LIVE_KAFKA=1 and create hammerfall.phase12_5.verify" if example.metadata[:live_kafka] && ENV["PHASE12_5_LIVE_KAFKA"] != "1"
  end

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

  it "keeps transport trace context outside the versioned event and continues it in audit" do
    skip "run with OTEL_ENABLED=true" unless Observability.enabled?

    auction = active_auction
    acknowledge_setup_events(auction)
    root = { "traceparent" => "00-#{SecureRandom.hex(16)}-#{SecureRandom.hex(8)}-01" }
    Observability.with_carrier(root) { auction.place_bid!(bidder: @bidder, amount: 10_000) }
    event = event_for(auction)
    expect(event.traceparent).to start_with("00-")
    expect(event.kafka_envelope.keys).not_to include(:traceparent, :tracestate)
    producer = fake_producer
    options = nil
    allow(producer).to receive(:produce) do |args|
      options = args
      double(wait: Object.new)
    end
    expect(KafkaOutboxPublisher.new(producer: producer, batch_size: 1).run_once[:published]).to eq(1)
    expect(options.fetch(:headers).fetch("traceparent")[3, 32]).to eq(event.traceparent[3, 32])
    expect(JSON.parse(options.fetch(:payload)).keys).not_to include("traceparent", "tracestate")
    broker = double("consumer", store_offset: nil, commit: nil)
    message = Struct.new(:payload, :key, :partition, :offset, :headers).new(
      options.fetch(:payload), auction.id.to_s, 0, 1, options.fetch(:headers))
    observed_trace = nil
    allow(ConsumedKafkaEvent).to receive(:record!).and_wrap_original do |original, **args|
      observed_trace = OpenTelemetry::Trace.current_span.context.hex_trace_id
      original.call(**args)
    end
    expect(KafkaAuditConsumer.new(consumer: broker).process(message)).to be_in([ :first, :next, :gap ])
    expect(observed_trace).to eq(event.traceparent[3, 32])
    expect(broker).to have_received(:commit).once
  end

  it "ignores malformed Kafka trace headers while committing a valid event" do
    auction = active_auction
    event = event_for(auction)
    broker = double("consumer", store_offset: nil, commit: nil)
    message = Struct.new(:payload, :key, :partition, :offset, :headers).new(
      JSON.generate(event.kafka_envelope), auction.id.to_s, 0, 1,
      { "traceparent" => "invalid", "baggage" => "private=secret" })
    expect(KafkaAuditConsumer.new(consumer: broker).process(message)).to eq(:first)
    expect(broker).to have_received(:commit).once
  end

  it "commits a versioned public event with the command and excludes private data" do
    auction = active_auction
    before = auction.public_revision
    IdempotentBidding.call(key: "kafka-bid", actor_id: @bidder.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000)
    event = event_for(auction)
    expect(event).to have_attributes(public_revision: before + 1, domain_event_type: "auction.price_changed.v2",
      kafka_published_at: nil, kafka_attempts: 0)
    expect(event.kafka_envelope).to include(event_id: event.event_id, aggregate_id: auction.id,
      aggregate_version: auction.reload.public_revision, schema_version: 2)
    expect(event.domain_payload).to include("status" => "active", "current_price" => 10_000)
    expect(event.kafka_envelope[:data].keys).not_to include("maximum_amount", "priority_sequence", "origin", "key_digest", "request_fingerprint")
    expect(IdempotencyRecord.where(actor_id: @bidder.id).pick(:status)).to eq("completed")
    expect(KafkaEventCodec.decode(JSON.generate(event.kafka_envelope), key: auction.id.to_s)["event_id"]).to eq(event.event_id)
  end

  it "rejects impossible public snapshots before a Kafka consumer accepts them" do
    auction = active_auction
    event = event_for(auction).kafka_envelope.stringify_keys
    data = event.fetch("data")
    invalid = [
      { "current_price" => data.fetch("starting_price") - 1 },
      { "starts_at" => data.fetch("ends_at") },
      { "original_ends_at" => data.fetch("starts_at") },
      { "ends_at" => (Time.iso8601(data.fetch("original_ends_at")) - 1).iso8601(6) },
      { "closed_at" => data.fetch("ends_at") },
      { "winner_id" => @bidder.id },
      { "status" => "closed" },
      { "title" => "   " }
    ]
    invalid.each do |change|
      candidate = event.deep_dup
      candidate.fetch("data").merge!(change)
      expect { KafkaEventCodec.decode(JSON.generate(candidate), key: auction.id.to_s) }
        .to raise_error(KafkaEventCodec::InvalidEvent, /invalid public data/)
    end

    auction.place_bid!(bidder: @bidder, amount: 10_000)
    closed = event_for(expire_fixture(auction).close!).kafka_envelope.stringify_keys
    closed.fetch("data")["winner_id"] = nil
    expect { KafkaEventCodec.decode(JSON.generate(closed), key: auction.id.to_s) }
      .to raise_error(KafkaEventCodec::InvalidEvent, /invalid public data/)
  end

  it "validates v2 reserve closure without accepting a raw reserve field" do
    auction = active_auction(reserve_price: 50_000)
    auction.place_bid!(bidder: @bidder, amount: 40_000)
    expire_fixture(auction).close!
    event = event_for(auction).kafka_envelope.stringify_keys
    expect(event.dig("data", "reserve_status")).to eq("not_met")
    expect(event.dig("data", "current_leader_id")).to eq(@bidder.id)
    expect(event.dig("data", "winner_id")).to be_nil
    expect(KafkaEventCodec.decode(JSON.generate(event), key: auction.id.to_s)).to eq(event)
    [ { "winner_id" => @bidder.id }, { "reserve_status" => "unknown" },
      { "reserve_price" => 50_000 } ].each do |change|
      candidate = event.deep_dup
      candidate.fetch("data").merge!(change)
      expect { KafkaEventCodec.decode(JSON.generate(candidate), key: auction.id.to_s) }
        .to raise_error(KafkaEventCodec::InvalidEvent)
    end
  end

  it "keeps committed event identity and payload immutable while allowing publisher acknowledgments" do
    event = event_for(active_auction)
    { event_id: SecureRandom.uuid, event_type: "auction.other.v1", schema_version: 2,
      auction_id: event.auction_id + 1,
      public_revision: event.public_revision + 1, domain_event_type: "auction.closed.v2",
      domain_payload: event.domain_payload.merge("status" => "closed"),
      occurred_at: event.occurred_at + 1 }.each do |field, value|
      expect { event.update!(field => value) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(event.reload.public_revision).to be_positive
    end
    event.domain_payload["status"] = "closed"
    event.save!
    expect(event.reload.domain_payload.fetch("status")).to eq("active")
    expect { event.update!(published_at: Time.current, kafka_published_at: Time.current) }.not_to raise_error
  end

  it "rejects unknown domain types and non-object payloads at the database boundary" do
    event = event_for(active_auction)
    [ { domain_event_type: "auction.unknown.v1" }, { domain_event_type: "auction.closed.v1" },
      { domain_payload: [ "invalid" ] } ].each do |change|
      expect do
        ApplicationRecord.transaction(requires_new: true) { OutboxEvent.where(id: event.id).update_all(change) }
      end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation) }
    end
  end

  it "classifies public terms, lifecycle and closure snapshots without a winner invention" do
    auction = create_auction
    @auction_ids << auction.id
    auction.edit_draft!(title: "Updated public title")
    expect(event_for(auction).domain_event_type).to eq("auction.terms_changed.v2")
    expect(event_for(auction).domain_payload["title"]).to eq("Updated public title")
    auction.schedule!
    expect(event_for(auction).domain_event_type).to eq("auction.status_changed.v2")
    auction.activate!
    expect(event_for(auction).domain_event_type).to eq("auction.status_changed.v2")
    expire_fixture(auction).close!
    expect(event_for(auction).domain_event_type).to eq("auction.closed.v2")
    expect(event_for(auction).domain_payload).to include("status" => "closed", "winner_id" => nil)
  end

  it "classifies a deadline-only public change as an extension" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    prior_price = auction.reload.current_price
    auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
    expect(auction.reload.current_price).to eq(prior_price)
    expect(event_for(auction).domain_event_type).to eq("auction.extended.v2")
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

  it "places the chaos boundary after delivery confirmation and before Kafka SQL acknowledgment" do
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    delivered = false
    producer = double("producer")
    allow(producer).to receive(:produce) do
      double(wait: nil).tap do |handle|
        allow(handle).to receive(:wait) { delivered = true; Object.new }
      end
    end
    allow(ChaosCrash).to receive(:at!) do |boundary, event_id|
      expect([ boundary, event_id, delivered ]).to eq([ "kafka_delivered", event.event_id, true ])
      expect(event.reload.kafka_published_at).to be_nil
      raise Interrupt, "simulated process death"
    end
    expect { KafkaOutboxPublisher.new(producer: producer, batch_size: 1).run_once }
      .to raise_error(Interrupt, "simulated process death")
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
    message = Struct.new(:payload, :key, :partition, :offset).new(JSON.generate(event.merge("schema_version" => 3)), auction.id.to_s, 0, 12)
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

  it "places the audit chaos boundary after durable effect and before offset commit" do
    auction = active_auction
    event = event_for(auction)
    broker = double("consumer", store_offset: nil, commit: nil)
    message = Struct.new(:payload, :key, :partition, :offset).new(
      JSON.generate(event.kafka_envelope), auction.id.to_s, 0, 1)
    allow(ChaosCrash).to receive(:at!) do |boundary, event_id|
      expect([ boundary, event_id ]).to eq([ "audit_effect_committed", event.event_id ])
      expect(ConsumedKafkaEvent.where(event_id: event.event_id).count).to eq(1)
      expect(KafkaAuditEntry.where(event_id: event.event_id).count).to eq(1)
      raise IOError, "simulated process death"
    end
    consumer = KafkaAuditConsumer.new(consumer: broker)
    expect { consumer.process(message) }.to raise_error(IOError, "simulated process death")
    expect(broker).not_to have_received(:store_offset)
    expect(broker).not_to have_received(:commit)
    allow(ChaosCrash).to receive(:at!).and_call_original
    expect(consumer.process(message)).to eq(:duplicate)
    expect(ConsumedKafkaEvent.where(event_id: event.event_id).count).to eq(1)
    expect(KafkaAuditEntry.where(event_id: event.event_id).count).to eq(1)
    expect(broker).to have_received(:commit).once
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

  it "holds a database transaction through Kafka delivery and temporarily excludes Sidekiq on the same row" do
    auction = active_auction
    OutboxEvent.where(auction_id: auction.id).update_all(published_at: Time.current, kafka_published_at: Time.current)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    entered = Queue.new
    release = Queue.new
    publisher_pid = Queue.new
    producer = double("slow Kafka producer")
    allow(producer).to receive(:produce) do
      entered << true
      release.pop
      double(wait: Object.new)
    end

    kafka = worker do |connection|
      pid = connection.select_value("SELECT pg_backend_pid()")
      publisher_pid << pid
      KafkaOutboxPublisher.new(producer: producer, batch_size: 1).run_once
    end
    take(entered)
    begin
      pid = take(publisher_pid)
      sleep 0.15 # Controlled dependency delay while the PostgreSQL transaction remains open.
      expect(OutboxEvent.connection.select_value("SELECT state FROM pg_stat_activity WHERE pid = #{Integer(pid)}")).to eq("idle in transaction")
      transaction_age = OutboxEvent.connection.select_value(
        "SELECT EXTRACT(EPOCH FROM clock_timestamp() - xact_start) FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
      )
      expect(transaction_age.to_f).to be >= 0.1
      Sidekiq.testing!(:fake) do
        AuctionChangedJob.clear
        expect(OutboxPublisher.new(batch_size: 1).run_once[:published]).to eq(0)
        expect(AuctionChangedJob.jobs).to be_empty
      end
      expect(event.reload).to have_attributes(published_at: nil, kafka_published_at: nil)
    ensure
      release << true
    end
    expect(result(kafka)[:published]).to eq(1)
    expect(event.reload.kafka_published_at).to be_present
    Sidekiq.testing!(:fake) do
      AuctionChangedJob.clear
      expect(OutboxPublisher.new(batch_size: 1).run_once[:published]).to eq(1)
      expect(AuctionChangedJob.jobs.size).to eq(1)
    ensure
      AuctionChangedJob.clear
    end
    expect(event.reload.published_at).to be_present
  end

  it "persists broker failure and acknowledges only a real broker delivery", :live_kafka do
    stub_const("KafkaOutboxPublisher::TOPIC", "hammerfall.phase12_5.verify")
    auction = active_auction
    acknowledge_setup_events(auction)
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = event_for(auction)
    unavailable = Rdkafka::Config.new("bootstrap.servers": "127.0.0.1:1", "message.timeout.ms": 1000).producer
    available = Rdkafka::Config.new("bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "127.0.0.1:29092"),
      "acks": "all", "message.timeout.ms": 5000).producer
    begin
      expect(KafkaOutboxPublisher.new(producer: unavailable, batch_size: 1).run_once[:failed]).to eq(1)
      expect(event.reload).to have_attributes(kafka_published_at: nil, kafka_attempts: 1)
      event.update!(kafka_next_attempt_at: 1.second.ago)
      expect(KafkaOutboxPublisher.new(producer: available, batch_size: 1).run_once[:published]).to eq(1)
      expect(event.reload).to have_attributes(kafka_attempts: 2, kafka_last_error: nil)
      expect(event.kafka_published_at).to be_present
      expect(event.event_id).to eq(event.reload.event_id)
    ensure
      unavailable.close
      available.close
    end
  end
end
