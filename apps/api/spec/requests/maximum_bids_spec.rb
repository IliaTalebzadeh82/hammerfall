require "rails_helper"
require "stringio"

RSpec.describe "Maximum bidding API privacy", :domain, type: :request do
  let(:auction) { create_auction(state: "active", minimum_increment: 1_000) }
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }
  let(:path) { "/api/v1/auctions/#{auction.id}/maximum-bid" }
  let(:secret) { 987_654 }

  def configure(user, amount)
    put path, params: { maximum_bid: { bidder_id: user.id, maximum_amount: amount } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
  end

  def expect_public_json
    expect(response.body).not_to include(secret.to_s, "maximum_amount", "priority_sequence", '"origin"', "automatic")
  end

  it "acknowledges configuration without disclosing ceilings or origins in public responses" do
    configure(alice, secret)
    expect(response).to have_http_status(:ok)
    expect(json).to eq("data" => { "auction_id" => auction.id, "bidder_id" => alice.id, "accepted" => true })
    expect_public_json
    configure(bob, 24_000)
    expect(response).to have_http_status(:ok)
    expect_public_json
    [ "/api/v1/auctions", "/api/v1/auctions/#{auction.id}", "/api/v1/auctions/#{auction.id}/bids" ].each do |url|
      get url
      expect(response).to have_http_status(:ok)
      expect_public_json
    end
    post "/api/v1/auctions/#{auction.id}/bids", params: { bid: { bidder_id: bob.id, amount: 30_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:created)
    expect_public_json
    expect(auction.reload).to have_attributes(current_price: 31_000, current_leader_id: alice.id)
  end

  it "does not disclose private maxima in stale, decrease or invalid-value errors" do
    configure(alice, secret)
    configure(bob, 5_000)
    expect(json.dig("error", "code")).to eq("maximum_bid_too_low")
    expect_public_json
    configure(alice, 30_000)
    expect(json.dig("error", "code")).to eq("maximum_bid_cannot_decrease")
    expect_public_json
    configure(bob, "invalid")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include(secret.to_s, "invalid")
  end

  it "has no maximum read or cancellation endpoint and rejects extra/private fields" do
    configure(alice, secret)
    get path
    expect(response).to have_http_status(:not_found)
    delete path
    expect(response).to have_http_status(:not_found)
    put path, params: { maximum_bid: { bidder_id: bob.id, maximum_amount: 30_000, priority_sequence: 1 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(auction.maximum_bids.count).to eq(1)
  end

  it "keeps repeated same-value protection unchanged and returns stable missing-actor errors" do
    configure(alice, secret)
    instruction = auction.maximum_bids.first.attributes
    configure(alice, secret)
    expect(response).to have_http_status(:ok)
    expect(auction.maximum_bids.first.attributes).to eq(instruction)
    put path, params: { maximum_bid: { bidder_id: 9_223_372_036_854_775_807, maximum_amount: 40_000 } }, headers: { "Idempotency-Key" => SecureRandom.uuid }, as: :json
    expect(json.dig("error", "code")).to eq("user_not_found")
  end

  it "filters request parameters, SQL bind values and model inspection from debug logs" do
    stream = StringIO.new
    logger = ActiveSupport::Logger.new(stream)
    previous_rails = Rails.logger
    previous_record = ActiveRecord::Base.logger
    previous_controller = ActionController::Base.logger
    begin
      Rails.logger = logger
      ActiveRecord::Base.logger = logger
      ActionController::Base.logger = logger
      configure(alice, secret)
      expect(response).to have_http_status(:ok)
      ActiveSupport::LogSubscriber.flush_all!
      expect(stream.string).to include("[FILTERED]")
      expect(stream.string).not_to include(secret.to_s)
      expect(auction.maximum_bids.first.inspect).not_to include(secret.to_s)
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("maximum_amount" => secret)
      expect(filtered.fetch("maximum_amount")).to eq("[FILTERED]")
    ensure
      Rails.logger = previous_rails
      ActiveRecord::Base.logger = previous_record
      ActionController::Base.logger = previous_controller
    end
  end
end
