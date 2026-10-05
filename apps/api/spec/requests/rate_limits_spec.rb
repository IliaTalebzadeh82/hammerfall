require "rails_helper"

RSpec.describe "Security rate limits", type: :request do
  it "rejects a login after its distributed IP budget without exposing the identifier" do
    user = User.create!(name: "Limit buyer", login: "limit-buyer", password: "local-test-password-only")
    10.times do
      post "/api/v1/session", params: { session: { login: "unknown-#{SecureRandom.hex(4)}", password: "wrong" } },
        headers: { "X-Hammerfall-Login" => "1" }, as: :json
      expect(response.status).to eq(401)
    end
    post "/api/v1/session", params: { session: { login: user.login, password: "local-test-password-only" } },
      headers: { "X-Hammerfall-Login" => "1" }, as: :json
    expect(response.status).to eq(429)
    expect(response.headers["Retry-After"]).to eq("60")
    expect(json.dig("error", "code")).to eq("rate_limited")
    expect(response.body).not_to include(user.login)
    expect(UserSession.count).to eq(0)
  end

  it "rejects a bid before claiming a new idempotency key" do
    user = User.create!(name: "Limited bidder")
    auction = create_auction(state: "active", closing_policy: "rapid")
    sign_in_as(user)
    path = "/api/v1/auctions/#{auction.id}/bids"
    20.times do
      post path, params: { bid: { amount: 10_000 } }, headers: auth_headers("Idempotency-Key" => "same-intention"), as: :json
      expect(response.status).to eq(201)
    end
    deadline_fixture(auction.reload, AuctionClock.now + 10)
    deadline = auction.ends_at
    revision = auction.public_revision
    post path, params: { bid: { amount: 11_000 } }, headers: auth_headers("Idempotency-Key" => "new-intention"), as: :json
    expect(response.status).to eq(429)
    expect(response.headers["Retry-After"]).to eq("10")
    expect(json.dig("error", "code")).to eq("rate_limited")
    expect(IdempotencyRecord.where(actor_id: user.id).count).to eq(1)
    expect(auction.bids.count).to eq(1)
    expect(auction.reload).to have_attributes(ends_at: deadline, public_revision: revision)
  end

  it "keeps an actor quota separate from another actor on the same IP" do
    first = User.create!(name: "First limited bidder")
    second = User.create!(name: "Second limited bidder")
    auction = create_auction(state: "active")
    path = "/api/v1/auctions/#{auction.id}/bids"
    sign_in_as(first)
    20.times do
      post path, params: { bid: { amount: 10_000 } }, headers: auth_headers("Idempotency-Key" => "first-intention"), as: :json
      expect(response.status).to eq(201)
    end
    post path, params: { bid: { amount: 11_000 } }, headers: auth_headers("Idempotency-Key" => "first-new"), as: :json
    expect(response.status).to eq(429)

    sign_in_as(second)
    post path, params: { bid: { amount: 11_000 } }, headers: auth_headers("Idempotency-Key" => "second-intention"), as: :json
    expect(response.status).to eq(201)
    expect(auction.bids.count).to eq(2)
  end
end
