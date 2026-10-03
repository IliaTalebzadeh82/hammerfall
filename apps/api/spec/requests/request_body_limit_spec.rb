require "rails_helper"

RSpec.describe "Pre-parse API request body limit", type: :request do
  let(:oversized) { "{" + ("x" * RequestBodyLimit::MAX_BYTES) + "}" }

  it "rejects oversized login before controller parsing" do
    post "/api/v1/session", params: oversized, headers: { "Content-Type" => "application/json", "X-Hammerfall-Login" => "1" }
    expect(response.status).to eq(413)
    expect(JSON.parse(response.body).dig("error", "code")).to eq("request_too_large")
    expect(UserSession.count).to eq(0)
  end

  it "rejects oversized manual and maximum commands without claims or bids" do
    user = User.create!(name: "Body limit buyer")
    auction = create_auction(state: "active")
    sign_in_as(user)
    [ [ :post, "/api/v1/auctions/#{auction.id}/bids" ],
      [ :put, "/api/v1/auctions/#{auction.id}/maximum-bid" ] ].each do |method, path|
      public_send(method, path, params: oversized, headers: auth_headers(
        "Content-Type" => "application/json", "Idempotency-Key" => "oversized-body"
      ))
      expect(response.status).to eq(413)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("request_too_large")
    end
    expect(IdempotencyRecord.count).to eq(0)
    expect(auction.bids).to be_empty
    expect(auction.maximum_bids).to be_empty
  end

  it "passes a valid just-below-limit login to the controller and keeps malformed smaller JSON at 400" do
    user = User.create!(name: "Bounded login", login: "bounded-login", password: "local-test-password-only")
    valid = JSON.generate(session: { login: user.login, password: "local-test-password-only" })
    valid += " " * (RequestBodyLimit::MAX_BYTES - valid.bytesize)
    post "/api/v1/session", params: valid, headers: { "Content-Type" => "application/json", "X-Hammerfall-Login" => "1" }
    expect(response.status).to eq(201)
    post "/api/v1/session", params: "{", headers: { "Content-Type" => "application/json", "X-Hammerfall-Login" => "1" }
    expect(response.status).to eq(400)
  end
end
