require "rails_helper"

RSpec.describe "Rapid closing", type: :model do
  let(:alice) { User.create!(name: "Rapid Alice") }
  let(:bob) { User.create!(name: "Rapid Bob") }

  it "extends one late manual command once even when a proxy response creates another row" do
    auction = create_auction(state: "active", closing_policy: "rapid", reserve_price: 50_000,
      increment_policy: "stepped")
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    deadline_fixture(auction, AuctionClock.now + 10)
    original = auction.ends_at
    auction.place_bid!(bidder: bob, amount: 60_000)
    expect(auction.reload).to have_attributes(ends_at: original + 10, current_price: 65_000,
      current_leader_id: alice.id)
    expect(auction.reserve_status).to eq("met")
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 50_000, 60_000, 65_000 ])
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last
    expect(event.domain_payload).to include("closing_policy" => "rapid", "reserve_status" => "met",
      "ends_at" => auction.ends_at.utc.iso8601(6))
    expect(event.domain_payload).not_to have_key("reserve_price")
    expect(event.domain_payload).not_to have_key("maximum_amount")
    expire_fixture(auction).close!
    expect(auction.reload.winner_id).to eq(alice.id)
  end

  it "extends a below-reserve bid and closes unsold if the reserve stays unmet" do
    auction = create_auction(state: "active", closing_policy: "rapid", reserve_price: 50_000)
    deadline_fixture(auction, AuctionClock.now + 10)
    original = auction.ends_at
    auction.place_bid!(bidder: alice, amount: 40_000)
    expect(auction.reload).to have_attributes(ends_at: original + 10, current_leader_id: alice.id)
    expect(auction.reserve_status).to eq("not_met")
    expire_fixture(auction).close!
    expect(auction.reload).to have_attributes(current_leader_id: alice.id, winner_id: nil)
  end

  it "does not extend stale, seller, or expired bids" do
    auction = create_auction(state: "active", closing_policy: "rapid", seller: alice,
      increment_policy: "stepped")
    deadline_fixture(auction, AuctionClock.now + 10)
    auction.place_bid!(bidder: bob, amount: 10_000)
    before = auction.reload.ends_at
    expect { auction.place_bid!(bidder: alice, amount: 15_000) }.to raise_error(DomainError)
    expect { auction.place_bid!(bidder: alice, amount: 9_000) }.to raise_error(DomainError)
    expect { auction.place_bid!(bidder: bob, amount: 10_000) }.to raise_error(DomainError)
    expect(auction.reload.ends_at).to eq(before)
    expire_fixture(auction)
    expired = auction.ends_at
    expect { auction.place_bid!(bidder: bob, amount: 20_000) }.to raise_error(DomainError)
    expect(auction.reload.ends_at).to eq(expired)
  end

  it "extends a new maximum once despite generated proxy rows and respects equal priority" do
    auction = create_auction(state: "active", closing_policy: "rapid", reserve_price: 50_000,
      increment_policy: "stepped")
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    deadline_fixture(auction, AuctionClock.now + 10)
    original = auction.ends_at
    auction.set_maximum!(bidder: bob, maximum_amount: 70_000)
    expect(auction.reload).to have_attributes(ends_at: original + 10, current_leader_id: alice.id)
    expect(auction.current_price).to eq(70_000)
    expect(auction.reserve_status).to eq("met")
    expect(auction.bids.maximum(:amount)).to be <= 70_000
  end

  it "extends a below-reserve maximum and a later reserve-crossing raise once each" do
    auction = create_auction(state: "active", closing_policy: "rapid", reserve_price: 50_000)
    deadline_fixture(auction, AuctionClock.now + 1)
    original = auction.ends_at
    auction.set_maximum!(bidder: alice, maximum_amount: 40_000)
    expect(auction.reload).to have_attributes(ends_at: original + 10, current_price: 40_000)
    expect(auction.reserve_status).to eq("not_met")
    expect(auction.bids.maximum(:amount)).to eq(40_000)
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    expect(auction.reload).to have_attributes(ends_at: original + 20, current_price: 50_000)
    expect(auction.reserve_status).to eq("met")
  end

  it "allows two genuine late commands to extend the effective deadline twice" do
    auction = create_auction(state: "active", closing_policy: "rapid")
    deadline_fixture(auction, AuctionClock.now + 1)
    original = auction.ends_at
    auction.place_bid!(bidder: alice, amount: 10_000)
    expect(auction.reload.ends_at).to eq(original + 10)
    auction.place_bid!(bidder: bob, amount: 10_500)
    expect(auction.reload.ends_at).to eq(original + 20)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 10_500 ])
  end

  it "rejects a stale stepped minimum after another bid crosses a price band without extending" do
    auction = create_auction(state: "active", closing_policy: "rapid", increment_policy: "stepped")
    deadline_fixture(auction, AuctionClock.now + 10)
    auction.place_bid!(bidder: alice, amount: 48_000)
    stale_minimum = auction.minimum_bid
    auction.place_bid!(bidder: bob, amount: 50_000)
    before = auction.reload.ends_at
    expect { auction.place_bid!(bidder: alice, amount: stale_minimum) }.to raise_error(DomainError) do |error|
      expect(error.code).to eq("bid_too_low")
      expect(error.details[:minimum_bid]).to be > stale_minimum
    end
    expect(auction.reload.ends_at).to eq(before)
  end
end
