require "rails_helper"

RSpec.describe AuctionChannel, type: :channel do
  it "streams only the requested existing public auction, without actor identity" do
    auction = create_auction
    other = create_auction
    subscribe(auction_id: auction.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("auction:#{auction.id}")
    expect(subscription).not_to have_stream_from("auction:#{other.id}")
    unsubscribe
    expect(subscription.streams).to be_empty
  end

  [ nil, "", "0", -1, 1.5, true, [], {}, "1oops", "1.0", "9" * 30, "9223372036854775807" ].each do |id|
    it "rejects malformed or unknown auction ID #{id.inspect}" do
      subscribe(auction_id: id)
      expect(subscription).to be_rejected
      expect(subscription.streams).to be_empty
    end
  end
end
