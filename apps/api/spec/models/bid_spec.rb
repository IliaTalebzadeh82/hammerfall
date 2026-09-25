require "rails_helper"

RSpec.describe Bid, :domain, type: :model do
  let(:auction) { create_auction(state: "active") }
  let(:bidder) { User.create!(name: "Alice") }

  it "accepts the starting price first and the increment boundary subsequently" do
    first = auction.place_bid!(bidder: bidder, amount: 10_000)
    expect(first.reload.amount).to eq(10_000)
    expect(auction.reload.current_price).to eq(first.amount)
    expect(auction.minimum_bid).to eq(10_500)
    second = auction.place_bid!(bidder: bidder, amount: 10_500)
    expect(auction.reload.current_price).to eq(second.amount)
    expect(auction.bids.order(:id).pluck(:amount)).to eq([ 10_000, 10_500 ])
  end

  it "allows a first bid above the starting price" do
    bid = auction.place_bid!(bidder: bidder, amount: 20_000)
    expect(auction.reload.current_price).to eq(bid.amount)
  end

  it "rejects low first and later bids without modifying either table" do
    expect { auction.place_bid!(bidder: bidder, amount: 9_999) }.to raise_error(DomainError) { |e| expect(e.details[:minimum_bid]).to eq(10_000) }
    auction.place_bid!(bidder: bidder, amount: 10_000)
    expect { auction.place_bid!(bidder: bidder, amount: 10_499) }.to raise_error(DomainError) { |e| expect(e.code).to eq("bid_too_low") }
    expect(auction.bids.count).to eq(1)
    expect(auction.reload.current_price).to eq(10_000)
  end

  it "refreshes a stale Ruby object between sequential operations" do
    stale = Auction.find(auction.id)
    auction.place_bid!(bidder: bidder, amount: 20_000)
    expect { stale.place_bid!(bidder: bidder, amount: 10_500) }.to raise_error(DomainError)
    expect(auction.reload.current_price).to eq(20_000)
  end

  %w[draft scheduled closed cancelled].each do |state|
    it "rejects bids on #{state} auctions" do
      inactive = create_auction(state: state)
      expect { inactive.place_bid!(bidder: bidder, amount: 10_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("invalid_auction_state") }
      expect(inactive.bids.count).to eq(0)
    end
  end

  it "rejects an elapsed window while status is still active" do
    expire_fixture(auction)
    expect { auction.place_bid!(bidder: bidder, amount: 10_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("auction_ended") }
    expect(auction.reload.status).to eq("active")
    expect(auction.bids).to be_empty
  end

  it "rejects an active fixture whose start is still in the future" do
    auction.update_columns(starts_at: AuctionClock.now + 30)
    expect { auction.place_bid!(bidder: bidder, amount: 10_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("auction_not_open") }
    expect(auction.bids).to be_empty
  end

  [ nil, 0, -1, 10_000.5, 10_000.0, "10000", "10000.5", false, MinorUnitsValidator::MAXIMUM + 1 ].each do |amount|
    it "rejects amount #{amount.inspect} without changing price/history" do
      expect { auction.place_bid!(bidder: bidder, amount: amount) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(auction.bids.count).to eq(0)
      expect(auction.reload.current_price).to eq(10_000)
    end
  end

  it "requires existing participants" do
    [ nil, User.new(name: "Unpersisted") ].each do |user|
      expect { auction.place_bid!(bidder: user, amount: 10_000) }.to raise_error(ActiveRecord::RecordInvalid)
    end
    bid = Bid.new(auction: nil, bidder: bidder, amount: 10_000)
    expect(bid.valid?(:placement)).to be(false)
    expect(bid.errors[:auction]).not_to be_empty
  end

  it "rejects direct creation that would omit the current-price write" do
    expect { Bid.create!(auction: auction, bidder: bidder, amount: 10_000) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "makes accepted bids immutable through normal persistence methods" do
    bid = auction.place_bid!(bidder: bidder, amount: 10_000)
    expect { bid.update!(amount: 11_000) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { bid.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { auction.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end

  it "rolls back the inserted bid if persisting current price fails" do
    auction
    bidder
    expect(auction).to receive(:save!).with(context: :bid_placement).and_raise(ActiveRecord::RecordInvalid.new(auction))
    expect { auction.place_bid!(bidder: bidder, amount: 12_000) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Bid.where(auction: auction).count).to eq(0)
    expect(auction.reload.current_price).to eq(10_000)
  end

  it "rolls back its bid even when an outer transaction rescues the failure" do
    auction
    bidder
    expect(auction).to receive(:save!).with(context: :bid_placement).and_raise(ActiveRecord::RecordInvalid.new(auction))
    ApplicationRecord.transaction do
      begin
        auction.place_bid!(bidder: bidder, amount: 12_000)
      rescue ActiveRecord::RecordInvalid
        # An outer application operation might deliberately handle this failure.
      end
      expect(Bid.where(auction: auction).count).to eq(0)
      expect(auction.reload.current_price).to eq(10_000)
    end
  end
end
