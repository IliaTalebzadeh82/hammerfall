require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Transactional public outbox", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  def events(auction)
    OutboxEvent.where(auction_id: auction.id).order(:public_revision)
  end

  it "commits exactly one public event with a bid, revision and idempotency outcome" do
    auction = active_auction
    before = events(auction).count
    command = -> { IdempotentBidding.call(key: "outbox-one", actor_id: @bidder.id, auction_id: auction.id, operation: "place_bid", amount: 10_000) }
    result = command.call
    expect(result.status).to eq(201)
    event = events(auction).last
    expect(events(auction).count).to eq(before + 1)
    expect(event).to have_attributes(event_type: "auction.changed.v1", schema_version: 1,
      public_revision: auction.reload.public_revision, published_at: nil, attempts: 0)
    expect(event.event_id).to be_present
    expect(event.attributes.to_json).not_to include("maximum_amount", "priority_sequence", "origin", "key_digest", "request_fingerprint")
    expect(auction.bids.count).to eq(1)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).pick(:status)).to eq("completed")
    expect(command.call.replayed).to be(true)
    expect(events(auction).count).to eq(before + 1)
  end

  it "rolls back event and domain state together, including nested savepoints" do
    auction = active_auction
    before = auction.public_revision
    ApplicationRecord.transaction do
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expect(events(auction).where(public_revision: before + 1).count).to eq(1)
      expect(result(worker { OutboxEvent.where(auction_id: auction.id, public_revision: before + 1).count })).to eq(0)
      raise ActiveRecord::Rollback
    end
    expect(auction.reload.public_revision).to eq(before)
    expect(auction.bids.count).to eq(0)
    expect(events(auction).where(public_revision: before + 1).count).to eq(0)
  end

  it "rolls back the authoritative mutation and idempotency claim if event insertion fails" do
    auction = active_auction
    before = auction.public_revision
    allow(OutboxEvent).to receive(:record_auction_change!).and_raise(IOError, "outbox insert failed")
    expect {
      IdempotentBidding.call(key: "outbox-insert-failure", actor_id: @bidder.id, auction_id: auction.id,
        operation: "place_bid", amount: 10_000)
    }.to raise_error(IOError, "outbox insert failed")
    expect(auction.reload.public_revision).to eq(before)
    expect(auction.bids.count).to eq(0)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).count).to eq(0)
    expect(events(auction).where(public_revision: before + 1).count).to eq(0)
  end

  it "does not create an event for private-only maximum increases or rejected bids" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    count = events(auction).count
    auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
    expect { auction.place_bid!(bidder: @bidder, amount: 9999) }.to raise_error(DomainError)
    expect(events(auction).count).to eq(count)
  end

  it "retains committed intent after the API returns and retries failed enqueue" do
    auction = active_auction
    OutboxPublisher.new.run_once
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = events(auction).last
    expect(event.published_at).to be_nil
    publisher = OutboxPublisher.new
    allow(AuctionChangedJob).to receive(:perform_async).and_raise(IOError, "Redis down")
    expect(publisher.run_once).to include(published: 0, failed: 1, backlog: 1, retries: 1)
    event.reload
    expect(event.last_error).to eq("IOError")
    expect(event.next_attempt_at).to be > Time.current
    expect(publisher.backlog_metrics).to include(backlog: 1, due: 0, retries: 1)
    event.update!(next_attempt_at: 1.second.ago)
    allow(AuctionChangedJob).to receive(:perform_async).and_call_original
    expect(publisher.run_once).to include(published: 1, failed: 0, backlog: 0)
    expect(event.reload.published_at).to be_present
    expect(auction.reload.current_price).to eq(10_000)
  end

  it "uses PostgreSQL time for retry and acknowledgment despite publisher clock skew" do
    auction = active_auction
    OutboxPublisher.new.run_once
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = events(auction).last
    db_before = ApplicationRecord.connection.select_value("SELECT clock_timestamp()")
    allow(Time).to receive(:current).and_return(db_before + 1.year)
    allow(AuctionChangedJob).to receive(:perform_async).and_raise(IOError, "Redis down")

    expect(OutboxPublisher.new.run_once[:failed]).to eq(1)
    expect(event.reload.next_attempt_at).to be_between(db_before, db_before + 30.seconds)
    expect(OutboxPublisher.new.backlog_metrics[:oldest_age_seconds]).to be < 60

    event.update!(next_attempt_at: ApplicationRecord.connection.select_value("SELECT clock_timestamp()") - 1.second)
    allow(AuctionChangedJob).to receive(:perform_async).and_call_original
    expect(OutboxPublisher.new.run_once[:published]).to eq(1)
    db_after = ApplicationRecord.connection.select_value("SELECT clock_timestamp()")
    expect(event.reload.published_at).to be_between(db_before, db_after)
  end

  it "may enqueue twice after an acknowledgment crash while preserving one outbox event" do
    auction = active_auction
    OutboxPublisher.new.run_once
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    event = events(auction).last
    Sidekiq.testing!(:fake) do
      AuctionChangedJob.clear
      allow_any_instance_of(OutboxEvent).to receive(:update!).and_raise(IOError, "ack crash")
      expect { OutboxPublisher.new.run_once }.to raise_error(IOError, "ack crash")
      expect(event.reload.published_at).to be_nil
      expect(AuctionChangedJob.jobs.size).to eq(1)
      allow_any_instance_of(OutboxEvent).to receive(:update!).and_call_original
      expect(OutboxPublisher.new.run_once[:published]).to eq(1)
      expect(AuctionChangedJob.jobs.size).to eq(2)
      expect(events(auction).where(public_revision: event.public_revision).count).to eq(1)
    ensure
      AuctionChangedJob.clear
    end
  end

  it "uses PostgreSQL skip-locked claims across concurrent publishers" do
    auction = active_auction
    OutboxPublisher.new.run_once
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    claimed = Queue.new
    release = Queue.new
    calls = Queue.new
    allow(AuctionChangedJob).to receive(:perform_async) do |id, revision|
      calls << [ id, revision ]
      claimed << true
      release.pop
      "queued-job"
    end
    first = worker { OutboxPublisher.new.run_once }
    take(claimed)
    expect(result(worker { OutboxPublisher.new.run_once })[:published]).to eq(0)
    release << true
    expect(result(first)[:published]).to eq(1)
    expect(calls.size).to eq(1)
    expect(events(auction).last.published_at).to be_present
  end

  it "lets another publisher advance a different row while the first claim is held" do
    auction = active_auction
    OutboxPublisher.new.run_once
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    first_revision = auction.reload.public_revision
    auction.place_bid!(bidder: @bidder, amount: 11_000)
    claimed = Queue.new
    release = Queue.new
    calls = Queue.new
    allow(AuctionChangedJob).to receive(:perform_async) do |_id, revision|
      calls << revision
      if revision == first_revision
        claimed << true
        release.pop
      end
      "queued-job"
    end

    first = worker { OutboxPublisher.new(batch_size: 1).run_once }
    take(claimed)
    expect(result(worker { OutboxPublisher.new(batch_size: 1).run_once })[:published]).to eq(1)
    expect(events(auction).where("public_revision >= ?", first_revision).where.not(published_at: nil).pluck(:public_revision)).to eq([ first_revision + 1 ])
    release << true
    expect(result(first)[:published]).to eq(1)
    expect(calls.size).to eq(2)
    expect(events(auction).where(published_at: nil)).to be_empty
  end
end
