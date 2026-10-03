require "rails_helper"

RSpec.describe AuctionChannel, type: :channel do
  before do
    user = User.create!(name: "Cable user")
    token = UserSession.issue!(user)
    row = UserSession.resolve(token)
    stub_connection(current_user: user, session_id: row.id)
  end

  it "streams only the requested existing public auction after authentication" do
    auction = create_auction
    other = create_auction
    subscribe(auction_id: auction.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("auction:#{auction.id}")
    expect(subscription).not_to have_stream_from("auction:#{other.id}")
    unsubscribe
    expect(subscription.streams).to be_empty
  end

  it "rejects a subscription after the session expires" do
    UserSession.update_all(created_at: 1.day.ago, expires_at: 1.minute.ago)
    subscribe(auction_id: create_auction.id)
    expect(subscription).to be_rejected
  end

  [ nil, "", "0", -1, 1.5, true, [], {}, "1oops", "1.0", "9" * 30, "9223372036854775807" ].each do |id|
    it "rejects malformed or unknown auction ID #{id.inspect}" do
      subscribe(auction_id: id)
      expect(subscription).to be_rejected
      expect(subscription.streams).to be_empty
    end
  end
end
