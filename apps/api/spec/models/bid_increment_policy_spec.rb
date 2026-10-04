require "rails_helper"

RSpec.describe "Stepped bid increments", :domain, type: :model do
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }

  it "uses the published current-price bands at exact euro boundaries" do
    cases = {
      1_000 => 100, 1_001 => 500, 10_000 => 500, 10_001 => 1_000,
      20_000 => 1_000, 20_001 => 2_000, 50_000 => 2_000,
      50_001 => 5_000, 100_000 => 5_000, 100_001 => 10_000,
      200_000 => 10_000, 200_001 => 20_000, 500_000 => 20_000,
      500_001 => 50_000, 1_000_000 => 50_000, 1_000_001 => 100_000,
      2_000_000 => 100_000, 2_000_001 => 200_000,
      5_000_000 => 200_000, 5_000_001 => 500_000,
      10_000_000 => 500_000, 10_000_001 => 1_000_000,
      20_000_000 => 1_000_000, 20_000_001 => 2_000_000,
      50_000_000 => 2_000_000, 50_000_001 => 5_000_000
    }
    auction = create_auction(increment_policy: "stepped")
    cases.each do |price, increment|
      expect(auction.bid_increment_policy.next_after(price)).to eq(price + increment)
    end
  end

  it "validates a manual offer from the locked price and publishes the current increment" do
    auction = create_auction(state: "active", increment_policy: "stepped", starting_price: 10_000)
    auction.place_bid!(bidder: alice, amount: 10_000)
    expect(auction.minimum_bid).to eq(10_500)
    expect { auction.place_bid!(bidder: bob, amount: 10_499) }.to raise_error(DomainError) { |error|
      expect(error.code).to eq("bid_too_low")
      expect(error.details).to eq(minimum_bid: 10_500, current_price: 10_000)
    }
    auction.place_bid!(bidder: bob, amount: 10_500)
    expect(auction.reload.minimum_bid).to eq(11_500)
    expect(Api::V1::AuctionPresenter.new(auction).as_json.fetch(:minimum_increment)).to eq(1_000)
    expect(OutboxEvent.where(auction_id: auction.id).last.domain_payload.fetch("minimum_increment")).to eq(1_000)
  end

  it "uses the loser's band for the smallest proxy counter and allows a partial ceiling" do
    auction = create_auction(state: "active", increment_policy: "stepped", starting_price: 10_000)
    auction.set_maximum!(bidder: alice, maximum_amount: 30_000)
    auction.set_maximum!(bidder: bob, maximum_amount: 20_001)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 20_001, 22_001 ])
    expect(auction.reload.current_leader_id).to eq(alice.id)
    auction.set_maximum!(bidder: bob, maximum_amount: 30_001)
    expect(auction.bids.order(:sequence).pluck(:amount).last(2)).to eq([ 30_000, 30_001 ])
    expect(auction.reload.current_leader_id).to eq(bob.id)
    expect(Api::V1::AuctionPresenter.new(auction).as_json.to_s).not_to include("maximum_amount")
    payload = OutboxEvent.where(auction_id: auction.id).last.domain_payload
    expect(payload).not_to include("maximum_amount", "priority_sequence", "increment_policy")
    expect(payload.fetch("minimum_increment")).to eq(2_000)
  end

  it "retains fixed increments for historical and default auctions" do
    auction = create_auction(state: "active", starting_price: 10_000, minimum_increment: 777)
    expect(auction.increment_policy).to eq("fixed")
    auction.place_bid!(bidder: alice, amount: 10_000)
    expect(auction.minimum_bid).to eq(10_777)
  end

  it "freezes the policy after scheduling and rejects invalid modes" do
    expect { create_auction(increment_policy: "unknown") }.to raise_error(ActiveRecord::RecordInvalid)
    auction = create_auction(state: "scheduled", increment_policy: "stepped")
    expect { auction.update!(increment_policy: "fixed") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(auction.reload.increment_policy).to eq("stepped")
  end
end
