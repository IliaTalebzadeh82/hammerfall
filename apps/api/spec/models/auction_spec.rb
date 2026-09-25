require "rails_helper"

RSpec.describe Auction, :domain, type: :model do
  it "creates a draft with an exact initial price and no winner" do
    auction = create_auction
    expect(auction.reload).to have_attributes(status: "draft", starting_price: 10_000, current_price: 10_000, winner_id: nil)
    expect(auction.minimum_bid).to eq(10_000)
  end

  %i[starting_price minimum_increment].each do |field|
    [ nil, 0, -1, 1.5, 100.0, "100", "100.5", true, MinorUnitsValidator::MAXIMUM + 1 ].each do |value|
      it "rejects #{field}=#{value.inspect} without truncating/coercing it" do
        expect { create_auction(**{ field => value }) }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  it "accepts bounded integer amounts" do
    auction = create_auction(starting_price: MinorUnitsValidator::MAXIMUM, minimum_increment: 1)
    expect(auction.reload.current_price).to eq(MinorUnitsValidator::MAXIMUM)
  end

  [ { title: " " }, { title: "x" * 201 }, { description: nil }, { description: "x" * 10_001 },
    { starts_at: nil }, { ends_at: nil }, { starts_at: "invalid" }, { ends_at: "invalid" } ].each do |attributes|
    it "rejects invalid attributes #{attributes.keys}" do
      expect { create_auction(**attributes) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "requires end strictly after start" do
    [ Time.current, 1.second.ago ].each do |finish|
      expect { create_auction(starts_at: Time.current, ends_at: finish) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "stores equivalent offset times in UTC" do
    auction = create_auction(starts_at: "2026-09-24T15:30:00+03:30", ends_at: "2026-09-24T16:30:00+03:30")
    expect(auction.reload.starts_at).to eq(Time.utc(2026, 9, 24, 12))
  end

  it "updates draft terms and keeps the no-bid current price equal to the start" do
    auction = create_auction
    auction.edit_draft!(title: "Updated", starting_price: 12_000)
    expect(auction.reload).to have_attributes(title: "Updated", starting_price: 12_000, current_price: 12_000)
  end

  %w[scheduled active closed cancelled].each do |state|
    it "freezes terms in #{state}" do
      auction = create_auction(state: state)
      expect { auction.edit_draft!(title: "Changed") }.to raise_error(DomainError) { |e| expect(e.code).to eq("invalid_auction_state") }
      expect { auction.update!(title: "Changed") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(auction.reload.title).to eq("Vintage camera")
    end
  end

  it "rejects normal saves that bypass lifecycle or price operations" do
    auction = create_auction
    [ { status: "active" }, { current_price: 12_000 }, { starting_price: 9_000 }, { winner_id: User.create!(name: "Alice").id } ].each do |change|
      expect { auction.update!(change) }.to raise_error(ActiveRecord::RecordInvalid)
      auction.reload
    end
    expect { Auction.create!(auction_attributes.merge(status: "active", current_price: 10_000)) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  # Each edge and each disallowed edge is tested independently of TRANSITIONS.
  allowed = { "draft" => %w[scheduled cancelled], "scheduled" => %w[active cancelled], "active" => %w[closed cancelled], "closed" => [], "cancelled" => [] }
  actions = { "scheduled" => :schedule!, "active" => :activate!, "closed" => :close!, "cancelled" => :cancel! }
  allowed.each do |source, targets|
    actions.each do |target, action|
      it "#{source} -> #{target} follows the documented lifecycle" do
        auction = create_auction(state: source)
        expire_fixture(auction) if source == "active" && target == "closed"
        if targets.include?(target) || source == target
          auction.public_send(action)
          expect(auction.reload.status).to eq(target)
        else
          expect { auction.public_send(action) }.to raise_error(DomainError) { |e| expect(e.code).to eq("invalid_state_transition") }
          expect(auction.reload.status).to eq(source)
        end
      end
    end
  end

  it "rejects scheduling an already-ended window" do
    auction = create_auction(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    expect { auction.schedule! }.to raise_error(DomainError)
  end

  it "requires an open database-time window for activation" do
    future = create_auction(state: "scheduled", starts_at: AuctionClock.now + 600)
    expect { future.activate! }.to raise_error(DomainError)
    ended = create_auction(state: "scheduled")
    expire_fixture(ended)
    expect { ended.activate! }.to raise_error(DomainError)
    open = create_auction(state: "scheduled")
    open.activate!
    expect(open.reload.status).to eq("active")
  end

  it "leaves an early close unchanged and closes a due auction without a winner" do
    auction = create_auction(state: "active")
    auction.close!
    expect(auction.reload).to have_attributes(status: "active", closed_at: nil)
    expire_fixture(auction).close!
    expect(auction.reload).to have_attributes(status: "closed", winner_id: nil)
    expect(auction.closed_at).to be >= auction.ends_at
    expect(auction.current_price).to eq(auction.starting_price)
  end

  it "distinguishes the current leader from the final winner" do
    auction = create_auction(state: "active")
    alice = User.create!(name: "Alice")
    bob = User.create!(name: "Bob")
    auction.place_bid!(bidder: alice, amount: 10_000)
    auction.place_bid!(bidder: bob, amount: 11_000)
    expect(auction.reload.winner).to be_nil
    expect(auction.leading_bid.bidder).to eq(bob)
    expect { auction.cancel! }.to raise_error(DomainError)
    expire_fixture(auction).close!
    expect(auction.reload.winner).to eq(bob)
    timestamp = auction.updated_at
    auction.close!
    expect(auction.reload).to have_attributes(winner_id: bob.id, updated_at: timestamp)
  end

  it "leaves an expired active auction active until explicitly closed" do
    auction = create_auction(state: "active")
    expire_fixture(auction)
    expect(auction.reload.status).to eq("active")
    auction.close!
    expect(auction.reload.status).to eq("closed")
  end
end
