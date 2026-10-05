require "rails_helper"

RSpec.describe "Recovery traffic fence", type: :request do
  it "returns a controlled 503 for public reads and mutations before they touch authority" do
    auction = create_auction(state: "active")
    bidder = User.create!(name: "Bidder")
    sign_in_as(bidder)
    revision = auction.public_revision
    bids = Bid.where(auction_id: auction.id).count
    commands = IdempotencyRecord.count
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("RECOVERY_FENCE").and_return("true")

    get "/api/v1/auctions/#{auction.id}"
    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig("error", "code")).to eq("recovery_in_progress")
    expect(response.headers["Cache-Control"]).to eq("no-store")

    post "/api/v1/auctions/#{auction.id}/bids", params: { bid: { amount: 11_000 } },
      headers: auth_headers("Idempotency-Key" => "fenced-bid"), as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig("error", "code")).to eq("recovery_in_progress")
    expect(response.headers["Retry-After"]).to eq("60")
    expect(auction.reload.public_revision).to eq(revision)
    expect(Bid.where(auction_id: auction.id).count).to eq(bids)
    expect(IdempotencyRecord.count).to eq(commands)
  end
end
