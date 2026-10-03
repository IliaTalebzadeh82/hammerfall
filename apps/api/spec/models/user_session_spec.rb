require "rails_helper"

RSpec.describe UserSession, type: :model do
  it "persists only a digest, rejects malformed tokens and prunes only expired rows" do
    user = User.create!(name: "Alice")
    token = UserSession.issue!(user)
    row = UserSession.resolve(token)
    expect(row).to be_present
    expect(row.attributes.to_json).not_to include(token)
    expect(UserSession.resolve("wrong")).to be_nil
    expect(UserSession.prune_expired!).to eq(0)
    row.update_columns(created_at: 1.day.ago, expires_at: 1.minute.ago)
    expect(UserSession.resolve(token)).to be_nil
    expect(UserSession.prune_expired!).to eq(1)
  end
end
