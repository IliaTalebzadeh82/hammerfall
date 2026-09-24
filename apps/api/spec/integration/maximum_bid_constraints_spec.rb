require "rails_helper"

RSpec.describe "Maximum bidding database constraints", :domain do
  let(:auction) { create_auction(state: "active") }
  let(:bidder) { User.create!(name: "Alice") }

  def reject_sql(type, &operation)
    expect { ApplicationRecord.transaction(requires_new: true, &operation) }.to raise_error(ActiveRecord::StatementInvalid) do |error|
      expect(error.cause).to be_a(type)
    end
  end

  def row
    { auction_id: auction.id, bidder_id: bidder.id, maximum_amount: 30_000, priority_sequence: 1, created_at: Time.current, updated_at: Time.current }
  end

  %i[auction_id bidder_id maximum_amount priority_sequence].each do |field|
    it "requires #{field}" do
      attributes = row.merge(field => nil)
      reject_sql(PG::NotNullViolation) { MaximumBid.insert_all!([ attributes ]) }
    end
  end

  [ { maximum_amount: 0 }, { maximum_amount: MinorUnitsValidator::MAXIMUM + 1 }, { priority_sequence: 0 } ].each do |invalid|
    it "enforces positive bounded maximum/priority #{invalid.keys}" do
      attributes = row.merge(invalid)
      reject_sql(PG::CheckViolation) { MaximumBid.insert_all!([ attributes ]) }
    end
  end

  %i[auction_id bidder_id].each do |field|
    it "enforces #{field} references" do
      attributes = row.merge(field => -1)
      reject_sql(PG::ForeignKeyViolation) { MaximumBid.insert_all!([ attributes ]) }
    end
  end

  it "enforces one instruction per bidder and unique auction-local priority" do
    attributes = row
    MaximumBid.insert_all!([ attributes ])
    reject_sql(PG::UniqueViolation) { MaximumBid.insert_all!([ attributes.merge(priority_sequence: 2) ]) }
    other = User.create!(name: "Bob")
    reject_sql(PG::UniqueViolation) { MaximumBid.insert_all!([ attributes.merge(bidder_id: other.id) ]) }
  end

  it "requires a valid bid origin and leader reference" do
    bid = auction.place_bid!(bidder: bidder, amount: 10_000)
    reject_sql(PG::CheckViolation) { Bid.where(id: bid.id).update_all(origin: "unknown") }
    reject_sql(PG::NotNullViolation) { Bid.where(id: bid.id).update_all(origin: nil) }
    reject_sql(PG::ForeignKeyViolation) { Auction.where(id: auction.id).update_all(current_leader_id: -1) }
    expect { auction.update!(current_leader_id: nil) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
