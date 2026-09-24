require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "PostgreSQL concurrent maximum bidding", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  before do
    @other = User.create!(name: "Other proxy bidder")
    @user_ids << @other.id
  end

  def compete(left, right)
    ready = Queue.new
    start = Queue.new
    threads = [ left, right ].map do |operation|
      worker do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        take(start)
        operation.call
      end
    end
    expect([ take(ready), take(ready) ].uniq.length).to eq(2)
    2.times { start << true }
    threads.map { |thread| result(thread) }
  end

  def max_command(auction, user, amount)
    -> { Auction.find(auction.id).set_maximum!(bidder: User.find(user.id), maximum_amount: amount) }
  end

  def assert_settled(auction, price:, leader:)
    auction.reload
    expect(auction).to have_attributes(current_price: price, current_leader_id: leader, winner_id: nil)
    rows = auction.bids.order(:sequence).to_a
    expect(rows.map(&:sequence)).to eq((1..rows.length).to_a)
    expect(rows.map(&:amount)).to eq(rows.map(&:amount).sort)
    expect(rows.last).to have_attributes(amount: price, bidder_id: leader)
    rows.select { |bid| bid.origin == "automatic" }.each do |bid|
      expect(bid.amount).to be <= auction.maximum_bids.find_by!(bidder_id: bid.bidder_id).maximum_amount
    end
    priorities = auction.maximum_bids.pluck(:priority_sequence)
    expect(priorities.uniq).to eq(priorities)
  end

  it "serializes different maxima on separate connections" do
    auction = active_auction(minimum_increment: 1_000)
    results = compete(max_command(auction, @bidder, 30_000), max_command(auction, @other, 40_000))
    expect(results).to all(be_a(MaximumBid))
    assert_settled(auction, price: 31_000, leader: @other.id)
  end

  it "resolves equal maxima by durable commitment priority" do
    auction = active_auction(minimum_increment: 1_000)
    compete(max_command(auction, @bidder, 30_000), max_command(auction, @other, 30_000))
    first = auction.maximum_bids.order(:priority_sequence).first
    expect(auction.maximum_bids.order(:priority_sequence).pluck(:priority_sequence)).to eq([ 1, 2 ])
    assert_settled(auction, price: 30_000, leader: first.bidder_id)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 30_000, 30_000 ])
  end

  [ 25_000, 35_000 ].each do |manual_amount|
    it "serializes a manual bid #{manual_amount} against a maximum" do
      auction = active_auction(minimum_increment: 1_000)
      manual = -> { Auction.find(auction.id).place_bid!(bidder: User.find(@other.id), amount: manual_amount) }
      outcomes = compete(max_command(auction, @bidder, 30_000), manual)
      if manual_amount < 30_000
        expect(outcomes).to contain_exactly(a_kind_of(MaximumBid), a_kind_of(Bid))
        assert_settled(auction, price: 26_000, leader: @bidder.id)
      else
        # A new maximum below an already committed manual price is rejected.
        expect(outcomes.last).to be_a(Bid)
        expect(outcomes.first).to be_a(MaximumBid).or be_a(DomainError)
        assert_settled(auction, price: 35_000, leader: @other.id)
      end
    end
  end

  it "serializes a protection increase against a challenger" do
    auction = active_auction(minimum_increment: 1_000)
    max_command(auction, @bidder, 30_000).call
    results = compete(max_command(auction, @bidder, 50_000), max_command(auction, @other, 40_000))
    expect(results).to all(be_a(MaximumBid))
    assert_settled(auction, price: 41_000, leader: @bidder.id)
  end

  it "serializes two existing bidders increasing to equal ceilings" do
    auction = active_auction(minimum_increment: 1_000)
    max_command(auction, @bidder, 30_000).call
    max_command(auction, @other, 40_000).call
    compete(max_command(auction, @bidder, 50_000), max_command(auction, @other, 50_000))
    expect(auction.maximum_bids.pluck(:maximum_amount)).to eq([ 50_000, 50_000 ])
    winner = auction.maximum_bids.order(:priority_sequence).first
    assert_settled(auction, price: 50_000, leader: winner.bidder_id)
  end

  it "never loses a larger same-user increase or duplicates the instruction" do
    auction = active_auction
    max_command(auction, @bidder, 30_000).call
    results = compete(max_command(auction, @bidder, 40_000), max_command(auction, @bidder, 50_000))
    expect(results.grep(DomainError).map(&:code) - [ "maximum_bid_cannot_decrease" ]).to be_empty
    expect(auction.maximum_bids.count).to eq(1)
    expect(auction.maximum_bids.first.maximum_amount).to eq(50_000)
    assert_settled(auction, price: 10_000, leader: @bidder.id)
  end

  %w[cancelled closed].each do |state|
    it "rechecks #{state} status after waiting on the auction lock" do
      auction = active_auction
      ready = Queue.new
      waiting = nil
      ApplicationRecord.transaction do
        auction.reload(lock: true)
        waiting = worker do |connection|
          stale = Auction.find(auction.id)
          ready << connection.select_value("SELECT pg_backend_pid()")
          stale.set_maximum!(bidder: User.find(@other.id), maximum_amount: 40_000)
        end
        wait_for_lock(take(ready))
        state == "closed" ? auction.close!(at: auction.ends_at) : auction.cancel!
      end
      error = result(waiting)
      expect(error).to be_a(DomainError)
      expect(error.code).to eq("invalid_auction_state")
      expect(auction.maximum_bids.count).to eq(0)
      expect(auction.bids.count).to eq(0)
    end
  end

  it "rolls back private state, priority, both visible rows, price and leader on SQL failure" do
    auction = active_auction(minimum_increment: 1_000)
    max_command(auction, @bidder, 30_000).call
    connection = ApplicationRecord.connection
    connection.add_check_constraint(:auctions, "id <> #{auction.id} OR current_price <> 31000", name: "test_proxy_failure")
    begin
      thread = worker do
        ApplicationRecord.transaction do
          expect { max_command(auction, @other, 40_000).call }.to raise_error(ActiveRecord::StatementInvalid) do |error|
            expect(error.cause).to be_a(PG::CheckViolation)
          end
        end
      end
      result(thread)
      expect(auction.maximum_bids.pluck(:bidder_id, :priority_sequence)).to eq([ [ @bidder.id, 1 ] ])
      assert_settled(auction, price: 10_000, leader: @bidder.id)
      expect(auction.bids.count).to eq(1)
    ensure
      connection.remove_check_constraint(:auctions, name: "test_proxy_failure")
    end
    result(worker { max_command(auction, @other, 40_000).call })
    expect(auction.maximum_bids.order(:priority_sequence).pluck(:priority_sequence)).to eq([ 1, 2 ])
    assert_settled(auction, price: 31_000, leader: @other.id)
  end
end
