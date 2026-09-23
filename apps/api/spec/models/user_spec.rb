require "rails_helper"

RSpec.describe User, :domain, type: :model do
  it "keeps identity to a display name and generated ID" do
    user = User.create!(name: "Alice")
    expect(user.reload.name).to eq("Alice")
    expect(User.create!(name: "Alice").id).not_to eq(user.id)
  end

  [ nil, "", "  ", "a" * 101 ].each do |name|
    it "rejects invalid name #{name.inspect}" do
      expect(User.new(name: name)).not_to be_valid
    end
  end

  it "preserves bidders referenced by accepted bids" do
    user = User.create!(name: "Alice")
    create_auction(state: "active").place_bid!(bidder: user, amount: 10_000)
    expect { user.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
