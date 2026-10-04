require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "PostgreSQL deadline races", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  it "lets a reserve-meeting bid win the lock, extending before a stale closer can finalize" do
    auction = active_auction(reserve_price: 50_000)
    auction.place_bid!(bidder: @bidder, amount: 40_000)
    deadline_fixture(auction, AuctionClock.now + 1)
    original = auction.ends_at
    ready = Queue.new
    closing = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      auction.place_bid!(bidder: @bidder, amount: 50_000)
      expect(auction.reserve_status).to eq("met")
      wait_until_database_time(original)
      closing = worker do |connection|
        stale = Auction.find(auction.id)
        expect(stale.reserve_status).to eq("not_met")
        ready << connection.select_value("SELECT pg_backend_pid()")
        stale.close!
      end
      wait_for_lock(take(ready))
    end
    expect(result(closing)).to be_a(Auction)
    expect(auction.reload).to have_attributes(status: "active", current_price: 50_000, winner_id: nil)
    expire_fixture(auction).close!
    expect(auction.reload).to have_attributes(status: "closed", current_leader_id: @bidder.id, winner_id: @bidder.id)
  end

  it "closes below reserve before a waiting bid and rejects the post-close bid" do
    auction = active_auction(reserve_price: 50_000)
    auction.place_bid!(bidder: @bidder, amount: 40_000)
    expire_fixture(auction)
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.close!
      waiting = worker do |connection|
        stale = Auction.find(auction.id)
        expect(stale.status).to eq("active")
        ready << connection.select_value("SELECT pg_backend_pid()")
        stale.place_bid!(bidder: User.find(@bidder.id), amount: 50_000)
      end
      wait_for_lock(take(ready))
    end
    expect(result(waiting)).to have_attributes(code: "invalid_auction_state")
    expect(auction.reload).to have_attributes(status: "closed", current_price: 40_000,
      current_leader_id: @bidder.id, winner_id: nil)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 40_000 ])
  end

  %i[manual maximum].each do |kind|
    it "rechecks a stale due candidate after a #{kind} action extends under the first lock" do
      auction = active_auction
      auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000) if kind == :maximum
      deadline_fixture(auction, AuctionClock.now + 1)
      original = auction.ends_at
      ready = Queue.new
      closing = nil
      ApplicationRecord.transaction do
        auction.reload(lock: true)
        if kind == :manual
          auction.place_bid!(bidder: @bidder, amount: 10_000)
        else
          auction.set_maximum!(bidder: @bidder, maximum_amount: 50_000)
        end
        expect(auction.ends_at).to eq(original + 90)
        wait_until_database_time(original)
        closing = worker do |connection|
          # READ COMMITTED discovery sees the old, now-due committed version.
          expect(AuctionCloser.new.candidate_ids).to include(auction.id)
          stale = Auction.find(auction.id)
          expect(stale.ends_at).to eq(original)
          ready << connection.select_value("SELECT pg_backend_pid()")
          stale.close!
        end
        wait_for_lock(take(ready))
      end
      expect(result(closing)).to be_a(Auction)
      expect(auction.reload).to have_attributes(status: "active", closed_at: nil, winner_id: nil,
        current_leader_id: @bidder.id, original_ends_at: original, ends_at: original + 90)
      expect(auction.bids.count).to eq(1)
    end

    it "rejects a waiting #{kind} after the closer wins the lock and finalizes" do
      auction = active_auction
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expire_fixture(auction)
      ready = Queue.new
      waiting = nil
      finalized = nil
      ApplicationRecord.transaction do
        auction.close!
        finalized = auction.closed_at
        waiting = worker do |connection|
          stale = Auction.find(auction.id)
          expect(stale.status).to eq("active")
          ready << connection.select_value("SELECT pg_backend_pid()")
          if kind == :manual
            stale.place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
          else
            stale.set_maximum!(bidder: User.find(@bidder.id), maximum_amount: 50_000)
          end
        end
        wait_for_lock(take(ready))
      end
      expect(result(waiting)).to have_attributes(code: "invalid_auction_state")
      expect(auction.reload).to have_attributes(status: "closed", winner_id: @bidder.id,
        current_leader_id: @bidder.id, closed_at: finalized, current_price: 10_000)
      expect(auction.bids.count).to eq(1)
      expect(auction.maximum_bids).to be_empty
    end

    it "rejects #{kind} begun before expiry but acquiring its lock after the real DB deadline" do
      auction = active_auction(ends_at: AuctionClock.now + 1)
      ready = Queue.new
      waiting = nil
      ApplicationRecord.transaction do
        auction.reload(lock: true)
        waiting = worker do |connection|
          ApplicationRecord.transaction do
            started = connection.select_value("SELECT transaction_timestamp()")
            ready << [ connection.select_value("SELECT pg_backend_pid()"), started ]
            if kind == :manual
              Auction.find(auction.id).place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
            else
              Auction.find(auction.id).set_maximum!(bidder: User.find(@bidder.id), maximum_amount: 50_000)
            end
          end
        end
        pid, started = take(ready)
        expect(started).to be < auction.ends_at
        wait_for_lock(pid)
        wait_until_database_time(auction.ends_at)
      end
      expect(result(waiting)).to have_attributes(code: "auction_ended")
      expect(auction.reload).to have_attributes(status: "active", current_price: 10_000, current_leader_id: nil)
      expect(auction.ends_at).to eq(auction.original_ends_at)
      expect(auction.bids).to be_empty
      expect(auction.maximum_bids).to be_empty
      auction.close!
      expect(auction.reload).to have_attributes(status: "closed", winner_id: nil)
    end
  end

  it "serializes many closers into one stable finalization with no synthetic bids" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    expire_fixture(auction)
    ready = Queue.new
    proceed = Queue.new
    threads = Array.new(8) do
      worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        take(proceed)
        closed = Auction.find(auction.id).close!
        [ closed.winner_id, closed.closed_at, closed.updated_at ]
      end
    end
    expect([ take(ready), take(ready) ].uniq.size).to eq(2)
    8.times { proceed << true }
    outcomes = threads.map { |thread| result(thread) }
    expect(outcomes.uniq.size).to eq(1)
    expect(outcomes.first.first).to eq(@bidder.id)
    expect(auction.bids.count).to eq(1)
    expect(auction.reload.closed_at).to be >= auction.ends_at
  end

  %i[manual maximum].each do |kind|
    it "rolls back #{kind} private/public state and the calculated extension on real SQL failure" do
      auction = active_auction(minimum_increment: 1_000)
      auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
      other = User.create!(name: "Rollback challenger")
      @user_ids << other.id
      deadline_fixture(auction, AuctionClock.now + 30)
      before = auction.reload.attributes
      maxima = auction.maximum_bids.map(&:attributes)
      connection = ApplicationRecord.connection
      # Final UPDATE includes the calculated +90; reject that value itself.
      connection.add_check_constraint(:auctions, "id <> #{auction.id} OR ends_at = original_ends_at", name: "test_reject_extension")
      begin
        failed = worker do
          expect do
            if kind == :manual
              Auction.find(auction.id).place_bid!(bidder: other, amount: 40_000)
            else
              Auction.find(auction.id).set_maximum!(bidder: other, maximum_amount: 40_000)
            end
          end.to raise_error(ActiveRecord::StatementInvalid) { |e| expect(e.cause).to be_a(PG::CheckViolation) }
        end
        result(failed)
        expect(auction.reload.attributes).to eq(before)
        expect(auction.maximum_bids.reload.map(&:attributes)).to eq(maxima)
        expect(auction.bids.pluck(:sequence, :amount)).to eq([ [ 1, 10_000 ] ])
      ensure
        connection.remove_check_constraint(:auctions, name: "test_reject_extension")
      end
    end
  end
end
