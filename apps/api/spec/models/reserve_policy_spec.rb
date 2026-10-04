require "rails_helper"

RSpec.describe "Hidden reserve policy", :domain, type: :model do
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }
  let(:auction) { create_auction(state: "active", starting_price: 10_000, reserve_price: 50_000, increment_policy: "stepped") }

  it "accepts a manual bid below reserve and closes unsold with its highest bidder retained" do
    expect(auction.reserve_status).to eq("not_met")
    auction.place_bid!(bidder: alice, amount: 20_000)
    expect(auction.reload).to have_attributes(current_price: 20_000, current_leader_id: alice.id, winner_id: nil)
    expect(auction.reserve_status).to eq("not_met")
    expire_fixture(auction).close!
    expect(auction.reload).to have_attributes(status: "closed", current_leader_id: alice.id, winner_id: nil)
    expect(auction.reserve_status).to eq("not_met")
    timestamp = auction.updated_at
    auction.close!
    expect(auction.reload.updated_at).to eq(timestamp)
  end

  it "reveals a below-reserve ceiling but only the reserve for an authorized higher ceiling" do
    auction.set_maximum!(bidder: alice, maximum_amount: 40_000)
    expect(auction.reload).to have_attributes(current_price: 40_000, current_leader_id: alice.id)
    expect(auction.reserve_status).to eq("not_met")
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    expect(auction.reload.current_price).to eq(50_000)
    expect(auction.reserve_status).to eq("met")
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 40_000, 50_000 ])
    expire_fixture(auction).close!
    expect(auction.reload.winner_id).to eq(alice.id)
  end

  it "opens a new maximum at reserve without displaying its unused ceiling" do
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    expect(auction.reload.current_price).to eq(50_000)
    expect(auction.reserve_status).to eq("met")
    expect(auction.bids.pluck(:amount)).to eq([ 50_000 ])
  end

  it "advances an existing manual leader to a lower new ceiling while still unmet" do
    auction.place_bid!(bidder: alice, amount: 30_000)
    auction.set_maximum!(bidder: alice, maximum_amount: 45_000)
    expect(auction.reload.current_price).to eq(45_000)
    expect(auction.reserve_status).to eq("not_met")
  end

  it "settles competing stepped maxima above reserve at the loser-based counter" do
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    auction.set_maximum!(bidder: bob, maximum_amount: 60_000)
    expect(auction.reload).to have_attributes(current_price: 65_000, current_leader_id: alice.id)
    expect(auction.reserve_status).to eq("met")
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 50_000, 60_000, 65_000 ])
  end

  [ [ 10_000, 11_001 ], [ 20_000, 22_001 ], [ 50_000, 55_001 ], [ 100_000, 110_001 ] ].each do |reserve, expected|
    it "uses the band above a #{reserve}-cent reserve for a competing ceiling" do
      boundary = create_auction(state: "active", starting_price: 1_000,
        reserve_price: reserve, increment_policy: "stepped")
      boundary.set_maximum!(bidder: alice, maximum_amount: reserve + 20_000)
      boundary.set_maximum!(bidder: bob, maximum_amount: reserve + 1)
      expect(boundary.reload).to have_attributes(current_price: expected, current_leader_id: alice.id)
      expect(boundary.reserve_status).to eq("met")
      expect(boundary.bids.order(:sequence).pluck(:amount)).to eq([ reserve, reserve + 1, expected ])
    end
  end

  it "caps a partial counter at the earlier bidder's ceiling" do
    auction.set_maximum!(bidder: alice, maximum_amount: 62_000)
    auction.set_maximum!(bidder: bob, maximum_amount: 60_000)
    expect(auction.reload).to have_attributes(current_price: 62_000, current_leader_id: alice.id)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 50_000, 60_000, 62_000 ])
    auction.bids.where(origin: "automatic").each do |bid|
      expect(bid.amount).to be <= auction.maximum_bids.find_by!(bidder_id: bid.bidder_id).maximum_amount
    end
  end

  it "keeps earlier durable priority when reserve-qualified maxima tie" do
    auction.set_maximum!(bidder: alice, maximum_amount: 70_000)
    auction.set_maximum!(bidder: bob, maximum_amount: 70_000)
    expect(auction.reload).to have_attributes(current_price: 70_000, current_leader_id: alice.id)
    expect(auction.maximum_bids.find_by!(bidder: alice).priority_sequence).to be <
      auction.maximum_bids.find_by!(bidder: bob).priority_sequence
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 50_000, 70_000, 70_000 ])
  end

  it "works with fixed increments and keeps no-reserve auctions unchanged" do
    fixed = create_auction(state: "active", reserve_price: 50_000, minimum_increment: 1_000)
    fixed.set_maximum!(bidder: alice, maximum_amount: 70_000)
    fixed.set_maximum!(bidder: bob, maximum_amount: 60_000)
    expect(fixed.reload.current_price).to eq(61_000)
    expect(fixed.reserve_status).to eq("met")
    plain = create_auction(state: "active", minimum_increment: 1_000)
    plain.set_maximum!(bidder: alice, maximum_amount: 70_000)
    expect(plain.reload.current_price).to eq(10_000)
    expect(plain.reserve_status).to eq("none")
  end

  it "freezes reserve on scheduling and rejects invalid integer-cent configuration" do
    draft = create_auction(reserve_price: 50_000)
    draft.edit_draft!(reserve_price: 60_000)
    expect(draft.reload.reserve_price).to eq(60_000)
    draft.schedule!
    expect { draft.edit_draft!(reserve_price: 70_000) }.to raise_error(DomainError)
    expect { draft.update!(reserve_price: 70_000) }.to raise_error(ActiveRecord::RecordInvalid)
    %w[active closed].each do |state|
      frozen = create_auction(state: state, reserve_price: 50_000)
      expect { frozen.edit_draft!(reserve_price: nil) }.to raise_error(DomainError)
    end
    [ 0, -1, 1.5, 50_000.0, "50000", MinorUnitsValidator::MAXIMUM + 1, 9_999 ].each do |value|
      expect { create_auction(reserve_price: value) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
