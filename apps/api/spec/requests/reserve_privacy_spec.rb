require "rails_helper"
require "stringio"

RSpec.describe "Hidden reserve API privacy", type: :request do
  let(:seller) { User.create!(name: "Seller") }
  let(:other) { User.create!(name: "Other") }
  let(:reserve) { 654_321 }
  let(:path) { "/api/v1/auctions" }

  def expect_private(response_body)
    expect(response_body).not_to include(reserve.to_s, "reserve_price", "maximum_amount", "priority_sequence")
  end

  it "lets the owner configure only a draft while every ordinary GET remains public-only" do
    sign_in_as(seller)
    post path, params: { auction: auction_attributes(reserve_price: reserve) }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:created)
    auction = Auction.find(json.dig("data", "id"))
    expect(auction.reserve_price).to eq(reserve)
    expect(json.dig("data", "reserve_status")).to eq("not_met")
    expect_private(response.body)

    patch "#{path}/#{auction.id}", params: { auction: { reserve_price: reserve + 1 } }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(auction.reload.reserve_price).to eq(reserve + 1)
    expect(auction.public_revision).to eq(1)
    expect(OutboxEvent.where(auction_id: auction.id).last.domain_payload)
      .to include("reserve_status" => "not_met")
    expect_private(response.body)

    sign_in_as(other)
    get "#{path}/#{auction.id}"
    expect(json.dig("data", "reserve_status")).to eq("not_met")
    expect_private(response.body)
    patch "#{path}/#{auction.id}", params: { auction: { reserve_price: nil } }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(auction.reload.reserve_price).to eq(reserve + 1)

    sign_in_as(User.create!(name: "Operator", role: "operator"))
    post "#{path}/#{auction.id}/schedule", headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    sign_in_as(seller)
    patch "#{path}/#{auction.id}", params: { auction: { reserve_price: nil } }, headers: auth_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("invalid_auction_state")
    expect_private(response.body)
  end

  it "omits the private amount from bid, maximum, history, outbox, projection and Cable" do
    auction = create_auction(state: "active", reserve_price: reserve)
    sign_in_as(other)
    post "#{path}/#{auction.id}/bids", params: { bid: { amount: 20_000 } },
      headers: auth_headers("Idempotency-Key" => "reserve-bid"), as: :json
    expect(response).to have_http_status(:created)
    expect_private(response.body)
    put "#{path}/#{auction.id}/maximum-bid", params: { maximum_bid: { maximum_amount: 30_000 } },
      headers: auth_headers("Idempotency-Key" => "reserve-max"), as: :json
    expect(response).to have_http_status(:ok)
    expect_private(response.body)
    get "#{path}/#{auction.id}/bids"
    expect_private(response.body)
    get "#{path}/#{auction.id}"
    expect(json.dig("data", "reserve_status")).to eq("not_met")
    expect_private(response.body)

    events = OutboxEvent.where(auction_id: auction.id)
    expect(events.map(&:domain_payload).to_json).not_to include(reserve.to_s, "reserve_price")
    expect(events.last.kafka_envelope.to_json).not_to include(reserve.to_s, "reserve_price")
    public_data = Api::V1::AuctionPresenter.new(auction.reload).as_json
    expect(public_data).to include(reserve_status: "not_met")
    expect(public_data.to_json).not_to include(reserve.to_s, "reserve_price")
    expect(ActionCable.server).to receive(:broadcast) do |_stream, payload|
      expect(payload).to eq(type: "auction.changed.v1", auction_id: auction.id, revision: auction.public_revision)
    end
    AuctionPublication.broadcast(auction.id, auction.public_revision)
    expect(ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter("reserve_price" => reserve).fetch("reserve_price")).to eq("[FILTERED]")
    expect(auction.inspect).not_to include(reserve.to_s)
  end

  it "filters reserve configuration from representative SQL and application logs" do
    auction = create_auction
    stream = StringIO.new
    logger = ActiveSupport::Logger.new(stream)
    previous = [ Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger ]
    begin
      Rails.logger = ActiveRecord::Base.logger = ActionController::Base.logger = logger
      auction.edit_draft!(reserve_price: reserve)
      ActiveSupport::LogSubscriber.flush_all!
      expect(stream.string).not_to include(reserve.to_s)
      expect(stream.string).not_to include('"reserve_price":654321')
    ensure
      Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger = previous
    end
  end
end
