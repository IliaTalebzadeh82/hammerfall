require "rails_helper"

RSpec.describe "Operator auction diagnostics", type: :request do
  let(:auction) { create_auction(state: "active", reserve_price: 654_321) }
  let(:path) { "/api/v1/operator/auctions/#{auction.id}" }
  let(:redis) { RedisClient.config(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), timeout: 1).new_client }
  let(:key) { "#{AuctionPublicProjection::KEY_PREFIX}#{auction.id}" }

  after do
    redis.call("DEL", key) if defined?(@auction_id)
    redis.close
  end

  before do
    @auction_id = auction.id
    redis.call("DEL", key)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPERATOR_API_ENABLED").and_return("true")
  end

  it "is disabled by default on the ordinary public API deployment" do
    allow(ENV).to receive(:[]).with("OPERATOR_API_ENABLED").and_return(nil)
    get path
    expect(response).to have_http_status(:not_found)
    post "#{path}/reconcile", as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "denies anonymous users, bidders and sellers" do
    get path
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/reconcile", as: :json
    expect(response).to have_http_status(:unauthorized)

    [ User.create!(name: "Bidder"), User.create!(name: "Seller", role: "member") ].each do |user|
      sign_in_as(user)
      get path
      expect(response).to have_http_status(:forbidden)
      post "#{path}/reconcile", headers: auth_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    expect(OperatorActionAudit.count).to eq(0)
  end

  it "returns bounded authority and derived-state diagnostics without private values" do
    sign_in_as(User.create!(name: "Operator", role: "operator"))
    get path
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to include("auction_id" => auction.id, "status" => "active",
      "public_revision" => auction.public_revision, "projection" => { "status" => "missing" })
    expect(json.dig("data", "outbox")).to include("sidekiq_pending" => kind_of(Integer), "kafka_pending" => kind_of(Integer))
    expect(response.body).not_to match(/654321|reserve_price|maximum_amount|priority_sequence|domain_payload|event_id/)
  end

  it "repairs one missing projection, records the actor and target, and preserves auction authority" do
    operator = User.create!(name: "Operator", role: "operator")
    sign_in_as(operator)
    before_state = auction.attributes.slice("status", "current_price", "public_revision", "current_leader_id", "winner_id")
    post "#{path}/reconcile", headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.fetch("data")).to eq("auction_id" => auction.id, "result" => "repaired")
    expect(redis.call("GET", key)).to be_present
    expect(auction.reload.attributes.slice(*before_state.keys)).to eq(before_state)
    expect(OperatorActionAudit.last).to have_attributes(actor_id: operator.id, auction_id: auction.id,
      action: "reconcile_projection", result: "repaired")
    expect(OperatorActionAudit.last.created_at).to be_present
    expect(response.body).not_to include("654321", "reserve_price")
  end

  it "leaves an ahead projection untouched and audits operator review" do
    projection = AuctionPublicProjection.new(redis: redis)
    event = OutboxEvent.where(auction_id: auction.id).order(:public_revision).last.kafka_envelope.stringify_keys
    event["aggregate_version"] = auction.public_revision + 1
    projection.apply_event(event)
    ahead = redis.call("GET", key)
    sign_in_as(User.create!(name: "Operator", role: "operator"))

    post "#{path}/reconcile", headers: auth_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "result")).to eq("operator_review")
    expect(redis.call("GET", key)).to eq(ahead)
    expect(OperatorActionAudit.last.result).to eq("operator_review")
    expect(auction.reload.public_revision).to be < projection.read(auction.id).fetch("public_revision")
  end

  it "rejects a missing CSRF token before operational mutation" do
    sign_in_as(User.create!(name: "Operator", role: "operator"))
    post "#{path}/reconcile", as: :json
    expect(response).to have_http_status(:forbidden)
    expect(OperatorActionAudit.count).to eq(0)
  end
end
