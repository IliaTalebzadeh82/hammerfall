require "rails_helper"

RSpec.describe "Core domain database constraints", :domain do
  let(:auction) { create_auction }
  let(:bidder) { User.create!(name: "Alice") }

  def expect_database_rejection(error_class, &write)
    expect do
      ActiveRecord::Base.transaction(requires_new: true, &write)
    end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(error_class) }
  end

  [ { title: nil }, { starts_at: nil }, { ends_at: nil }, { starting_price: nil },
    { current_price: nil }, { minimum_increment: nil }, { status: nil }, { description: nil }, { closing_policy: nil } ].each do |attributes|
    it "enforces auction NOT NULL for #{attributes.keys.first}" do
      id = auction.id
      expect_database_rejection(PG::NotNullViolation) { Auction.where(id: id).update_all(attributes) }
    end
  end

  [ { title: "  " }, { status: "unknown" }, { closing_policy: "unknown" }, { starting_price: 0 }, { current_price: 0 },
    { minimum_increment: -1 }, { starting_price: MinorUnitsValidator::MAXIMUM + 1 },
    { current_price: MinorUnitsValidator::MAXIMUM + 1 }, { minimum_increment: MinorUnitsValidator::MAXIMUM + 1 },
    { current_price: 9_999 } ].each do |attributes|
    it "enforces auction CHECKs for #{attributes}" do
      id = auction.id
      expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(attributes) }
    end
  end

  it "enforces end after start" do
    id = auction.id
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(ends_at: auction.starts_at) }
  end

  it "enforces original end after start even when the effective end is later" do
    id = auction.id
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(original_ends_at: auction.starts_at) }
  end

  it "enforces winner only on closed auctions and requires an existing winner" do
    id = auction.id
    user_id = bidder.id
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(winner_id: user_id) }
    expect_database_rejection(PG::ForeignKeyViolation) { Auction.where(id: id).update_all(status: "closed", winner_id: -1, current_leader_id: -1, closed_at: auction.ends_at) }
  end

  it "permits a closed highest bidder without a sale and rejects reserve-inconsistent winners" do
    unsold = create_auction(state: "active", reserve_price: 50_000)
    unsold.place_bid!(bidder: bidder, amount: 40_000)
    expire_fixture(unsold).close!
    expect(unsold.reload).to have_attributes(current_leader_id: bidder.id, winner_id: nil)
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: unsold.id).update_all(winner_id: bidder.id) }

    sold = create_auction(state: "active", reserve_price: 50_000)
    sold.place_bid!(bidder: bidder, amount: 50_000)
    expire_fixture(sold).close!
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: sold.id).update_all(winner_id: nil) }
  end

  it "bounds reserve in SQL relative to the auction starting price" do
    id = auction.id
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(reserve_price: 9_999) }
    expect_database_rejection(PG::CheckViolation) { Auction.where(id: id).update_all(reserve_price: MinorUnitsValidator::MAXIMUM + 1) }
  end

  it "enforces nonblank, non-null user names independently of validation" do
    id = bidder.id
    expect_database_rejection(PG::CheckViolation) { User.where(id: id).update_all(name: "\t  ") }
    expect_database_rejection(PG::NotNullViolation) { User.where(id: id).update_all(name: nil) }
  end

  [ { sequence: 0 }, { sequence: -1 }, { amount: 0 }, { amount: -1 }, { amount: MinorUnitsValidator::MAXIMUM + 1 } ].each do |attributes|
    it "enforces bid CHECKs for #{attributes}" do
      row = { auction_id: auction.id, bidder_id: bidder.id, amount: 10_000, sequence: 1, created_at: Time.current }.merge(attributes)
      expect_database_rejection(PG::CheckViolation) { Bid.insert_all!([ row ]) }
    end
  end

  %i[auction_id bidder_id amount sequence created_at].each do |field|
    it "enforces bid NOT NULL for #{field}" do
      row = { auction_id: auction.id, bidder_id: bidder.id, amount: 10_000, sequence: 1, created_at: Time.current, field => nil }
      expect_database_rejection(PG::NotNullViolation) { Bid.insert_all!([ row ]) }
    end
  end

  %i[auction_id bidder_id].each do |field|
    it "enforces the bid #{field} foreign key" do
      row = { auction_id: auction.id, bidder_id: bidder.id, amount: 10_000, sequence: 1, created_at: Time.current, field => -1 }
      expect_database_rejection(PG::ForeignKeyViolation) { Bid.insert_all!([ row ]) }
    end
  end

  it "prevents raw deletion of auctions and users referenced by accepted bids" do
    active = create_auction(state: "active")
    user = bidder
    active.place_bid!(bidder: user, amount: 10_000)
    expect_database_rejection(PG::ForeignKeyViolation) { Auction.where(id: active.id).delete_all }
    expect_database_rejection(PG::ForeignKeyViolation) { User.where(id: user.id).delete_all }
  end

  it "enforces unique sequences within an auction, not across auctions" do
    active = create_auction(state: "active")
    first = active.place_bid!(bidder: bidder, amount: 10_000)
    row = first.attributes.except("id")
    expect_database_rejection(PG::UniqueViolation) { Bid.insert_all!([ row ]) }
    other = create_auction(state: "active")
    expect(other.place_bid!(bidder: bidder, amount: 10_000).sequence).to eq(1)
  end
end
