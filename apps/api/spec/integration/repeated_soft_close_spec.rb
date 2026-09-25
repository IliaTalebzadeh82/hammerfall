require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Repeated committed soft close", :slow, type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  it "extends in two real windows with separate commits and no intervening clock/deadline manipulation" do
    auction = active_auction(ends_at: AuctionClock.now + 2)
    bob = User.create!(name: "Later bidder")
    @user_ids << bob.id
    original = auction.ends_at
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    expect(ApplicationRecord.connection.open_transactions).to eq(0)
    # A separate session sees the actual committed extension, not a savepoint.
    first = result(worker { Auction.find(auction.id).ends_at })
    expect(first).to eq(original + 90)
    wait_until_database_time(first - 60)
    auction.place_bid!(bidder: bob, amount: 11_000)
    expect(ApplicationRecord.connection.open_transactions).to eq(0)
    second = result(worker { Auction.find(auction.id) })
    expect(second).to have_attributes(original_ends_at: original, ends_at: original + 180,
      current_leader_id: bob.id, current_price: 11_000)
    expect(second.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 11_000 ])
  end
end
