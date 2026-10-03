require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "PostgreSQL idempotency concurrency", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  def command(auction, amount: 10_000, operation: "place_bid", key: "same-key")
    IdempotentBidding.call(key: key, actor_id: @bidder.id, auction_id: auction.id, operation: operation, amount: amount)
  end

  def concurrent_commands(count = 10, &operation)
    ready = Queue.new
    start = Queue.new
    threads = Array.new(count) do |index|
      worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        take(start)
        operation.call(index)
      end
    end
    expect([ take(ready), take(ready) ].uniq.size).to eq(2)
    count.times { start << true }
    threads.map { |thread| result(thread) }
  end

  def expect_one_outcome(outcomes, status)
    expect(outcomes.map(&:status).uniq).to eq([ status ])
    expect(outcomes.map(&:body).uniq.size).to eq(1)
    expect(outcomes.count { |outcome| !outcome.replayed }).to eq(1)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).count).to eq(1)
  end

  it "coordinates ten identical manual requests into one committed bid and snapshot" do
    auction = active_auction
    outcomes = concurrent_commands { command(auction) }
    expect_one_outcome(outcomes, 201)
    expect(auction.bids.pluck(:sequence, :amount)).to eq([ [ 1, 10_000 ] ])
  end

  it "settles a proxy-generating late command once across ten duplicates" do
    auction = active_auction(minimum_increment: 1_000)
    other = User.create!(name: "Proxy incumbent")
    @user_ids << other.id
    auction.set_maximum!(bidder: other, maximum_amount: 30_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    original = auction.ends_at
    outcomes = concurrent_commands { command(auction, amount: 20_000) }
    expect_one_outcome(outcomes, 201)
    expect(auction.reload).to have_attributes(current_price: 21_000, current_leader_id: other.id, ends_at: original + 90)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 20_000, 21_000 ])
    expect(auction.maximum_bids.first).to have_attributes(maximum_amount: 30_000, priority_sequence: 1)
  end

  [ false, true ].each do |existing|
    it "applies a #{existing ? 'maximum increase' : 'new maximum'} and extension exactly once" do
      auction = active_auction
      auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000) if existing
      deadline_fixture(auction, AuctionClock.now + 30)
      original = auction.ends_at
      outcomes = concurrent_commands { command(auction, operation: "set_maximum_bid", amount: 50_000) }
      expect_one_outcome(outcomes, 200)
      expect(auction.maximum_bids.first).to have_attributes(maximum_amount: 50_000, priority_sequence: existing ? 2 : 1)
      expect(auction.bids.count).to eq(1)
      expect(auction.reload.ends_at).to eq(original + 90)
    end
  end

  %w[place_bid set_maximum_bid].each do |operation|
    it "allows only one of conflicting #{operation} payloads to establish a key" do
      auction = active_auction
      outcomes = concurrent_commands(2) { |index| command(auction, operation: operation, amount: [ 30_000, 40_000 ][index]) }
      expect(outcomes.map(&:status)).to contain_exactly(operation == "place_bid" ? 201 : 200, 409)
      winner = outcomes.index { |outcome| outcome.status != 409 }
      amount = [ 30_000, 40_000 ][winner]
      if operation == "place_bid"
        expect(auction.reload.current_price).to eq(amount)
      else
        expect(auction.maximum_bids.first.maximum_amount).to eq(amount)
      end
      expect(auction.bids.count).to eq(1)
      expect(IdempotencyRecord.where(actor_id: @bidder.id).count).to eq(1)
    end

    it "replays #{operation} after closure without waiting on a separately locked auction" do
      auction = active_auction
      original = command(auction, operation: operation, amount: 30_000)
      expire_fixture(auction).close!
      before = auction.attributes
      ApplicationRecord.transaction do
        auction.reload(lock: true)
        replay = result(worker { command(auction, operation: operation, amount: 30_000) })
        expect(replay).to have_attributes(status: original.status, body: original.body, replayed: true)
      end
      expect(auction.reload.attributes).to eq(before)
    end

    it "rolls back #{operation} mutation and ownership if snapshot persistence fails, then permits retry" do
      auction = active_auction
      deadline_fixture(auction, AuctionClock.now + 30)
      original = auction.reload.attributes
      connection = ApplicationRecord.connection
      connection.add_check_constraint(:idempotency_records, "actor_id <> #{@bidder.id} OR status <> 'completed'", name: "test_reject_outcome")
      begin
        failure = worker do
          expect { command(auction, operation: operation, amount: 30_000) }.to raise_error(ActiveRecord::StatementInvalid) do |error|
            expect(error.cause).to be_a(PG::CheckViolation)
          end
        end
        result(failure)
        expect(IdempotencyRecord.where(actor_id: @bidder.id)).to be_empty
        expect(auction.reload.attributes).to eq(original)
        expect(auction.bids).to be_empty
        expect(auction.maximum_bids).to be_empty
      ensure
        connection.remove_check_constraint(:idempotency_records, name: "test_reject_outcome")
      end
      retried = command(auction, operation: operation, amount: 30_000)
      expect(retried.status).to eq(operation == "place_bid" ? 201 : 200)
      expect(retried.replayed).to be(false)
      expect(auction.reload.ends_at).to eq(original.fetch("ends_at") + 90)
      expect(auction.bids.pluck(:sequence)).to eq([ 1 ])
    end
  end

  it "waits on uncommitted logical-key ownership, not auction evaluation, and replays after owner commit" do
    auction = active_auction
    ready = Queue.new
    waiting = nil
    first = nil
    ApplicationRecord.transaction do
      first = command(auction)
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        command(auction)
      end
      pid = take(ready)
      wait_for_lock(pid)
      query = ApplicationRecord.connection.select_value("SELECT query FROM pg_stat_activity WHERE pid = #{pid.to_i}")
      expect(query).to include("pg_advisory_xact_lock")
    end
    expect(result(waiting)).to have_attributes(body: first.body, status: 201, replayed: true)
    expect(auction.bids.count).to eq(1)
  end

  it "lets a waiting duplicate become owner after the first owner's whole transaction rolls back" do
    auction = active_auction
    deadline_fixture(auction, AuctionClock.now + 30)
    original = auction.ends_at
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      command(auction)
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        command(auction)
      end
      wait_for_lock(take(ready))
      raise ActiveRecord::Rollback
    end
    expect(result(waiting)).to have_attributes(status: 201, replayed: false)
    expect(auction.bids.pluck(:sequence)).to eq([ 1 ])
    expect(auction.reload.ends_at).to eq(original + 90)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).count).to eq(1)
  end

  it "keeps a new key's decision clock fresh after an auction wait and replays the expired rejection" do
    auction = active_auction(ends_at: AuctionClock.now + 1)
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        command(auction)
      end
      wait_for_lock(take(ready))
      wait_until_database_time(auction.ends_at)
    end
    rejected = result(waiting)
    expect(rejected.status).to eq(422)
    expect(rejected.body.dig("error", "code")).to eq("auction_ended")
    auction.close!
    expect(command(auction)).to have_attributes(status: 422, body: rejected.body, replayed: true)
    expect(auction.bids).to be_empty
  end
end
