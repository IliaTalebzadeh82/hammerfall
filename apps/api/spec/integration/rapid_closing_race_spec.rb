require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Rapid closing PostgreSQL races", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  it "keeps the auction active when the late bid holds the lock ahead of a due closer" do
    auction = active_auction(closing_policy: "rapid", reserve_price: 50_000)
    deadline_fixture(auction, AuctionClock.now + 1)
    original = auction.ends_at
    ready = Queue.new
    closing = nil
    ApplicationRecord.transaction do
      auction.reload(lock: true)
      auction.place_bid!(bidder: @bidder, amount: 50_000)
      expect(auction.ends_at).to eq(original + 10)
      wait_until_database_time(original)
      closing = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        Auction.find(auction.id).close!
      end
      wait_for_lock(take(ready))
    end
    expect(result(closing)).to be_a(Auction)
    expect(auction.reload).to have_attributes(status: "active", ends_at: original + 10,
      current_leader_id: @bidder.id, winner_id: nil)
  end

  it "rejects a waiting bid after the closer holds the lock and finalizes" do
    auction = active_auction(closing_policy: "rapid", reserve_price: 50_000)
    auction.place_bid!(bidder: @bidder, amount: 40_000)
    expire_fixture(auction)
    ready = Queue.new
    waiting = nil
    ApplicationRecord.transaction do
      auction.close!
      waiting = worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        Auction.find(auction.id).place_bid!(bidder: User.find(@bidder.id), amount: 50_000)
      end
      wait_for_lock(take(ready))
    end
    expect(result(waiting)).to have_attributes(code: "invalid_auction_state")
    expect(auction.reload).to have_attributes(status: "closed", current_leader_id: @bidder.id,
      winner_id: nil)
    expect(auction.bids.count).to eq(1)
  end

  it "serializes two competing late bids into valid price and deadline outcomes" do
    auction = active_auction(closing_policy: "rapid", increment_policy: "stepped")
    deadline_fixture(auction, AuctionClock.now + 5)
    original = auction.ends_at
    other = User.create!(name: "Other rapid bidder")
    @user_ids << other.id
    ready = Queue.new
    start = Queue.new
    threads = [ [ @bidder.id, 10_000 ], [ other.id, 11_000 ] ].map do |bidder_id, amount|
      worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        take(start)
        Auction.find(auction.id).place_bid!(bidder: User.find(bidder_id), amount: amount)
      end
    end
    2.times { take(ready) }
    2.times { start << true }
    outcomes = threads.map { |thread| result(thread) }
    accepted = outcomes.count { |value| value.is_a?(Bid) }
    expect(accepted).to be >= 1
    expect(auction.reload.ends_at).to eq(original + 10 * accepted)
    expect(auction.current_price).to eq(auction.bids.maximum(:amount))
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq(auction.bids.order(:sequence).pluck(:amount).sort)
  end
end
