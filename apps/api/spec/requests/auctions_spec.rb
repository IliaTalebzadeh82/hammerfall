require "rails_helper"

RSpec.describe "Auction API", :domain, type: :request do
  let(:path) { "/api/v1/auctions" }

  it "creates a draft and deliberately serializes its public fields" do
    post path, params: { auction: auction_attributes }, as: :json
    expect(response).to have_http_status(:created)
    data = json.fetch("data")
    expect(data).to include("title" => "Vintage camera", "status" => "draft", "currency" => "EUR", "current_price" => 10_000, "current_leader_id" => nil, "winner_id" => nil)
    expect(data.keys).to match_array(%w[id public_revision title description status currency starting_price current_price minimum_increment starts_at ends_at original_ends_at closed_at current_leader_id winner_id created_at updated_at])
    expect(data["starts_at"]).to end_with("Z")
    get "#{path}/#{data.fetch('id')}", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to eq(data)
  end

  it "lists auctions in bounded pages without duplicating the cursor row" do
    records = Array.new(3) { create_auction }
    get path, params: { limit: 2 }
    expect(json.fetch("data").map { |record| record["id"] }).to eq(records.first(2).map(&:id))
    cursor = json.dig("meta", "next_after_id")
    expect(cursor).to eq(records[1].id)
    get path, params: { limit: 2, after_id: cursor }
    expect(json.fetch("data").map { |record| record["id"] }).to eq([ records.last.id ])
    expect(json.dig("meta", "next_after_id")).to be_nil
  end

  it "returns an empty collection and terminal cursor" do
    get path
    expect(json).to eq("data" => [], "meta" => { "next_after_id" => nil })
  end

  [ { limit: 0 }, { limit: 101 }, { limit: "oops" }, { after_id: -1 }, { after_id: "1oops" }, { after_id: "9" * 30 } ].each do |query|
    it "rejects invalid pagination #{query}" do
      get path, params: query
      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_request")
    end
  end

  it "edits a draft and synchronizes its starting/current price" do
    auction = create_auction
    patch "#{path}/#{auction.id}", params: { auction: { title: "Updated", starting_price: 12_000 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("title" => "Updated", "starting_price" => 12_000, "current_price" => 12_000)
  end

  it "uses explicit lifecycle endpoints and freezes scheduled terms" do
    auction = create_auction
    post "#{path}/#{auction.id}/activate", as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("invalid_state_transition")
    post "#{path}/#{auction.id}/schedule", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "status")).to eq("scheduled")
    post "#{path}/#{auction.id}/schedule", as: :json
    expect(response).to have_http_status(:ok)
    patch "#{path}/#{auction.id}", params: { auction: { title: "Changed" } }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("invalid_auction_state")
    post "#{path}/#{auction.id}/activate", as: :json
    expect(json.dig("data", "status")).to eq("active")
    post "#{path}/#{auction.id}/close", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "status")).to eq("active")
    expire_fixture(auction)
    post "#{path}/#{auction.id}/close", as: :json
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("status" => "closed", "winner_id" => nil)
  end

  it "cancels a draft and rejects later activation" do
    auction = create_auction
    post "#{path}/#{auction.id}/cancel", as: :json
    expect(json.dig("data", "status")).to eq("cancelled")
    post "#{path}/#{auction.id}/activate", as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns a stable not-found error without internal details" do
    get "#{path}/9223372036854775807", as: :json
    expect(response).to have_http_status(:not_found)
    expect(json).to eq("error" => { "code" => "auction_not_found", "message" => "Requested resource was not found.", "details" => {} })
  end

  it "returns validation fields and no record on invalid creation" do
    post path, params: { auction: auction_attributes(starting_price: 0, ends_at: 2.minutes.ago) }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("validation_failed")
    expect(json.dig("error", "details").keys).to include("starting_price", "ends_at")
    expect(Auction.count).to eq(0)
  end

  %w[status current_price winner_id id original_ends_at closed_at public_revision].each do |field|
    it "rejects client-written #{field} during both create and update" do
      post path, params: { auction: auction_attributes.merge(field => "closed") }, as: :json
      expect(response).to have_http_status(:bad_request)
      auction = create_auction
      patch "#{path}/#{auction.id}", params: { auction: { field => "closed" } }, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(auction.reload.status).to eq("draft")
    end
  end

  [ {}, { auction: [] }, { auction: "wrong" }, { auction: {} }, { auction: { title: [] } }, { auction: { title: { nested: "value" } } } ].each do |body|
    it "rejects malformed resource shape #{body}" do
      post path, params: body, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_request")
    end
  end

  it "returns JSON for malformed JSON input" do
    post path, params: '{"auction":', headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(json.dig("error", "code")).to eq("invalid_request")
  end
end
