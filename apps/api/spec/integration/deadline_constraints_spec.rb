require "rails_helper"

RSpec.describe "Deadline SQL integrity" do
  it "enforces original deadline, closure timestamp, final winner and nullability" do
    auction = create_auction(state: "active")
    user = User.create!(name: "Winner")
    [ { original_ends_at: nil }, { ends_at: auction.original_ends_at - 1 },
      { status: "closed" }, { closed_at: auction.ends_at },
      { status: "closed", closed_at: auction.ends_at - 1 },
      { status: "closed", closed_at: auction.ends_at, winner_id: user.id } ].each do |change|
      expect do
        ApplicationRecord.transaction(requires_new: true) { Auction.where(id: auction.id).update_all(change) }
      end.to raise_error(ActiveRecord::StatementInvalid) { |e| expect(e.cause).to be_a(PG::CheckViolation).or be_a(PG::NotNullViolation) }
    end
  end
end
