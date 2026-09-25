require "rails_helper"

RSpec.describe "Soft close", type: :model do
  let(:auction) { create_auction(state: "active", minimum_increment: 1_000) }
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }

  it "extends a two-row proxy contest once, preserving the original deadline" do
    auction.set_maximum!(bidder: alice, maximum_amount: 30_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    original = auction.ends_at
    auction.place_bid!(bidder: bob, amount: 20_000)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 20_000, 21_000 ])
    expect(auction.reload).to have_attributes(ends_at: original + 90, original_ends_at: original, current_leader_id: alice.id)
  end

  it "extends a first maximum and a two-row maximum challenge once each" do
    deadline_fixture(auction, AuctionClock.now + 30)
    first_end = auction.ends_at
    auction.set_maximum!(bidder: alice, maximum_amount: 30_000)
    expect(auction.reload.ends_at).to eq(first_end + 90)
    expect(auction.bids.count).to eq(1)
    deadline_fixture(auction, AuctionClock.now + 30)
    challenge_end = auction.ends_at
    auction.set_maximum!(bidder: bob, maximum_amount: 40_000)
    expect(auction.reload.ends_at).to eq(challenge_end + 90)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 30_000, 31_000 ])
  end

  it "extends new protection and a later increase without generating visible bids" do
    auction.place_bid!(bidder: alice, amount: 10_000)
    [ 30_000, 50_000 ].each do |maximum|
      # Independent fixture scenarios, not evidence that real time advanced.
      deadline_fixture(auction, AuctionClock.now + 30)
      original = auction.ends_at
      auction.set_maximum!(bidder: alice, maximum_amount: maximum)
      expect(auction.reload.ends_at).to eq(original + 90)
      expect(auction.bids.count).to eq(1)
    end
  end

  it "does not extend an identical maximum or any rejected action" do
    auction.set_maximum!(bidder: alice, maximum_amount: 30_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    before = auction.reload.attributes
    auction.set_maximum!(bidder: alice, maximum_amount: 30_000)
    expect { auction.set_maximum!(bidder: alice, maximum_amount: 20_000) }.to raise_error(DomainError)
    expect { auction.place_bid!(bidder: bob, amount: 9_999) }.to raise_error(DomainError)
    expect(auction.reload.attributes).to eq(before)
    expect(auction.bids.count).to eq(1)
  end

  it "does not extend an accepted action outside the final minute" do
    original = auction.ends_at
    auction.place_bid!(bidder: alice, amount: 10_000)
    expect(auction.reload.ends_at).to eq(original)
  end

  it "guards timing fields and final winner against ordinary updates" do
    auction.place_bid!(bidder: alice, amount: 10_000)
    [ { ends_at: auction.ends_at + 90 }, { original_ends_at: auction.original_ends_at + 90 }, { closed_at: AuctionClock.now } ].each do |change|
      expect { auction.update!(change) }.to raise_error(ActiveRecord::RecordInvalid)
      auction.reload
    end
    expire_fixture(auction).close!
    before = auction.attributes
    expect { auction.update!(winner_id: bob.id) }.to raise_error(ActiveRecord::RecordInvalid)
    expect { auction.set_maximum!(bidder: alice, maximum_amount: 50_000) }.to raise_error(DomainError)
    auction.close!
    expect(auction.reload.attributes).to eq(before)
  end

  it "keeps the original deadline synchronized while editing a draft" do
    draft = create_auction
    deadline = AuctionClock.now + 5000
    draft.edit_draft!(ends_at: deadline)
    expect(draft.reload.original_ends_at).to eq(draft.ends_at)
  end

  it "obtains fresh database clock readings even within Rails query caching" do
    ApplicationRecord.cache do
      first = AuctionClock.now
      ApplicationRecord.connection.execute("SELECT pg_sleep(0.02)")
      expect(AuctionClock.now).to be > first
    end
  end
end
