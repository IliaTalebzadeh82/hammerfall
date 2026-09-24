require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "PostgreSQL concurrent bidding", type: :model do
  # Only this group commits fixtures so other sessions can see them.
  self.use_transactional_tests = false

  include_context "committed auction concurrency"

  def simultaneous(auction, amounts)
    # Barrier precedes checkout: many contenders also work with the default pool of 3.
    ready = Queue.new
    start = Queue.new
    connected = Queue.new
    proceed = Queue.new
    users = amounts.map { User.create!(name: "Concurrent contender").id }
    @user_ids.concat(users)
    threads = amounts.each_with_index.map do |amount, index|
      Thread.new do
        ready << true
        take(start)
        ApplicationRecord.connection_pool.with_connection do |connection|
          pid = connection.select_value("SELECT pg_backend_pid()")
          connected << pid
          take(proceed)
          begin
            [ pid, Auction.find(auction.id).place_bid!(bidder: User.find(users[index]), amount: amount) ]
          rescue DomainError => error
            [ pid, error ]
          end
        end
      end.tap do |thread|
        thread.report_on_exception = false
        @threads << thread
      end
    end
    amounts.length.times { take(ready) }
    amounts.length.times { start << true }
    # Hold both available worker connections before either operation begins.
    expect(Array.new(2) { take(connected) }.uniq.length).to eq(2)
    amounts.length.times { proceed << true }
    threads.map { |thread| result(thread) }
  end

  def expect_consistent(auction, outcomes)
    bids = auction.bids.order(:sequence).to_a
    accepted = outcomes.grep(Bid)
    rejected = outcomes.grep(DomainError)
    expect(bids.map(&:id)).to match_array(accepted.map(&:id))
    expect(bids.map(&:sequence)).to eq((1..bids.length).to_a)
    expect(bids.first.amount).to be >= auction.starting_price
    bids.each_cons(2) { |left, right| expect(right.amount).to be >= left.amount + auction.minimum_increment }
    expect(rejected.map(&:code).uniq - [ "bid_too_low" ]).to be_empty
    expect(accepted.length + rejected.length).to eq(outcomes.length)
    expect(auction.reload.current_price).to eq(bids.last.amount)
    expect(auction.leading_bid.id).to eq(bids.last.id)
    expect(auction.winner_id).to be_nil
  end

  it "serializes two competing bids on independent committed connections" do
    auction = active_auction
    outcomes = simultaneous(auction, [ 11_000, 12_000 ])
    expect(outcomes.map(&:first).uniq.length).to eq(2)
    expect_consistent(auction, outcomes.map(&:last))
    expect(auction.current_price).to eq(12_000)
  end

  it "rejects a lower waiter using fresh state even with a preloaded stale Auction" do
    auction = active_auction
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      waiting = worker do |connection|
        stale = Auction.find(auction.id)
        expect(stale.current_price).to eq(10_000)
        ready << connection.select_value("SELECT pg_backend_pid()")
        stale.place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
      end
      wait_for_lock(take(ready))
      auction.place_bid!(bidder: User.find(@bidder.id), amount: 15_000)
    end
    error = result(waiting)
    expect(error).to be_a(DomainError)
    expect(error.code).to eq("bid_too_low")
    expect(error.details).to eq(current_price: 15_000, minimum_bid: 15_500)
    expect(auction.bids.pluck(:amount, :sequence)).to eq([ [ 15_000, 1 ] ])
    expect(auction.reload.current_price).to eq(15_000)
  end

  it "preserves price and ordering with many competing bidders" do
    auction = active_auction
    outcomes = simultaneous(auction, (0...12).map { |i| 10_000 + i * 500 }.shuffle)
    expect(outcomes.map(&:first).uniq.length).to be >= 2
    expect_consistent(auction, outcomes.map(&:last))
    expect(auction.current_price).to eq(15_500)
  end

  it "accepts exactly one of simultaneous same-amount bids" do
    auction = active_auction
    outcomes = simultaneous(auction, Array.new(8, 10_000)).map(&:last)
    expect(outcomes.grep(Bid).length).to eq(1)
    expect(outcomes.grep(DomainError).length).to eq(7)
    expect_consistent(auction, outcomes)
  end

  it "revalidates lifecycle status after a waiting bid acquires the lock" do
    auction = active_auction
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      waiting = worker do |connection|
        stale = Auction.find(auction.id)
        ready << connection.select_value("SELECT pg_backend_pid()")
        stale.place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
      end
      wait_for_lock(take(ready))
      auction.cancel!
    end
    error = result(waiting)
    expect(error).to be_a(DomainError)
    expect(error.code).to eq("invalid_auction_state")
    expect(error.details).to eq(status: "cancelled")
    expect(auction.reload).to have_attributes(status: "cancelled", current_price: 10_000)
    expect(auction.bids).to be_empty
  end

  it "lets a different auction finish while the first auction remains locked" do
    locked = active_auction
    independent = active_auction
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      locked.reload(lock: true)
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        Auction.find(locked.id).place_bid!(bidder: User.find(@bidder.id), amount: 11_000)
      end
      wait_for_lock(take(ready))
      other = worker { Auction.find(independent.id).place_bid!(bidder: User.find(@bidder.id), amount: 12_000) }
      expect(result(other)).to be_a(Bid)
      expect(independent.reload.current_price).to eq(12_000)
      expect(waiting).to be_alive
    end
    expect(result(waiting)).to be_a(Bid)
  end

  it "rolls back an inserted bid and sequence when the real price UPDATE fails" do
    auction = active_auction
    connection = ApplicationRecord.connection
    # Real database failure after INSERT, without mocking ActiveRecord or locking.
    connection.add_check_constraint(:auctions, "id <> #{auction.id} OR current_price <> 12000", name: "test_reject_price")
    begin
      failed = worker do
        ApplicationRecord.transaction do
          begin
            Auction.find(auction.id).place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
          rescue ActiveRecord::StatementInvalid => error
            expect(error.cause).to be_a(PG::CheckViolation)
          end
        end
      end
      result(failed)
      expect(auction.bids).to be_empty
      expect(auction.reload.current_price).to eq(10_000)
      bid = result(worker { Auction.find(auction.id).place_bid!(bidder: User.find(@bidder.id), amount: 13_000) })
      expect(bid.sequence).to eq(1)
      expect(auction.reload.current_price).to eq(13_000)
    ensure
      connection.remove_check_constraint(:auctions, name: "test_reject_price")
    end
  end

  it "samples time after waiting, rejecting a bid whose window expired" do
    auction = active_auction
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        Auction.find(auction.id).place_bid!(bidder: User.find(@bidder.id), amount: 12_000)
      end
      wait_for_lock(take(ready))
      travel_to(auction.ends_at + 1.second)
    end
    error = result(waiting)
    expect(error).to be_a(DomainError)
    expect(error.code).to eq("auction_not_open")
    expect(auction.bids).to be_empty
    expect(auction.reload.current_price).to eq(10_000)
  ensure
    travel_back
  end

  it "makes a waiting close select the last committed bidder as winner" do
    auction = active_auction
    ready = Queue.new
    closing = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      closing = worker do |connection|
        stale = Auction.find(auction.id)
        ready << connection.select_value("SELECT pg_backend_pid()")
        stale.close!(at: stale.ends_at)
      end
      wait_for_lock(take(ready))
      auction.place_bid!(bidder: User.find(@bidder.id), amount: 15_000)
    end
    expect(result(closing)).to be_a(Auction)
    expect(auction.reload).to have_attributes(status: "closed", winner_id: @bidder.id, current_price: 15_000)
    expect(auction.bids.pluck(:sequence)).to eq([ 1 ])
  end
end
