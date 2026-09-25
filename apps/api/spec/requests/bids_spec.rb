require "rails_helper"

RSpec.describe "Bidding API", :domain, type: :request do
  let(:auction) { create_auction(state: "active") }
  let(:bidder) { User.create!(name: "Alice") }
  let(:path) { "/api/v1/auctions/#{auction.id}/bids" }

  it "accepts a bid, exposes history and a leader, and sets a winner only at closure" do
    post path, params: { bid: { bidder_id: bidder.id, amount: 10_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    data = json.fetch("data")
    expect(data.keys).to match_array(%w[id auction_id bidder_id amount sequence currency created_at])
    expect(data).to include("bidder_id" => bidder.id, "amount" => 10_000, "currency" => "EUR", "sequence" => 1)
    get path
    expect(json.fetch("data")).to eq([ data ])
    get "/api/v1/auctions/#{auction.id}"
    expect(json.fetch("data")).to include("current_price" => 10_000, "current_leader_id" => bidder.id, "winner_id" => nil)
    expire_fixture(auction)
    post "/api/v1/auctions/#{auction.id}/close"
    expect(json.fetch("data")).to include("status" => "closed", "current_leader_id" => bidder.id, "winner_id" => bidder.id)
    post path, params: { bid: { bidder_id: bidder.id, amount: 11_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("invalid_auction_state")
    expect(auction.bids.count).to eq(1)
  end

  it "rejects a low bid with the required minimum, leaving state intact" do
    auction.place_bid!(bidder: bidder, amount: 10_000)
    post path, params: { bid: { bidder_id: bidder.id, amount: 10_499 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json).to eq("error" => { "code" => "bid_too_low", "message" => "Bid must be at least 10500 cents.", "details" => { "minimum_bid" => 10_500, "current_price" => 10_000 } })
    expect(auction.reload.current_price).to eq(10_000)
    expect(auction.bids.count).to eq(1)
  end

  [ 10_000.5, "10000", 0, nil, true, MinorUnitsValidator::MAXIMUM + 1 ].each do |amount|
    it "rejects invalid amount #{amount.inspect}" do
      post path, params: { bid: { bidder_id: bidder.id, amount: amount } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_failed")
      expect(auction.bids.count).to eq(0)
    end
  end

  it "reports missing auction and user distinctly" do
    post "/api/v1/auctions/9223372036854775807/bids", params: { bid: { bidder_id: bidder.id, amount: 10_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(json.dig("error", "code")).to eq("auction_not_found")
    post path, params: { bid: { bidder_id: 9_223_372_036_854_775_807, amount: 10_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(json.dig("error", "code")).to eq("user_not_found")
  end

  it "rejects missing identity and client timestamp overrides" do
    post path, params: { bid: { amount: 10_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:bad_request)
    post path, params: { bid: { bidder_id: bidder.id, amount: 10_000, created_at: 1.year.ago } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(auction.bids.count).to eq(0)
  end

  it "rejects an elapsed window even while status remains active" do
    expire_fixture(auction)
    post path, params: { bid: { bidder_id: bidder.id, amount: 10_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("auction_ended")
  end

  it "paginates history by authoritative sequence and scopes it to one auction" do
    other = create_auction(state: "active")
    other.place_bid!(bidder: bidder, amount: 50_000)
    first = auction.place_bid!(bidder: bidder, amount: 10_000)
    second = auction.place_bid!(bidder: bidder, amount: 10_500)
    get path, params: { limit: 1 }
    expect(json.fetch("data").map { |row| row["id"] }).to eq([ first.id ])
    get path, params: { limit: 1, after_sequence: first.sequence }
    expect(json.fetch("data").map { |row| row["id"] }).to eq([ second.id ])
    expect(json.dig("meta", "next_after_sequence")).to be_nil
  end

  it "rejects client sequences and invalid or obsolete history cursors" do
    post path, params: { bid: { bidder_id: bidder.id, amount: 10_000, sequence: 20 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:bad_request)
    [ { after_id: 1 }, { after_sequence: 0 }, { after_sequence: "oops" } ].each do |query|
      get path, params: query
      expect(response).to have_http_status(:bad_request)
    end
  end
end
