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

  it "stores a bcrypt digest and requires a distinct, sufficiently long login credential" do
    user = User.create!(name: "Alice", login: "alice-account", password: "private-password")
    expect(user.password_digest).not_to include("private-password")
    expect(user.authenticate("private-password")).to eq(user)
    expect(user.authenticate("wrong-password")).to be_falsey
    expect(User.new(name: "Other", login: "ALICE-ACCOUNT", password: "another-password")).not_to be_valid
    expect(User.new(name: "Short", login: "short-account", password: "short")).not_to be_valid
  end
end
