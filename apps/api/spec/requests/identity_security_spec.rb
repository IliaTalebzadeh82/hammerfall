require "rails_helper"
require "stringio"

RSpec.describe "Identity and auction authorization", type: :request do
  let(:buyer) { User.create!(name: "Buyer", login: "buyer-one", password: "buyer-password") }
  let(:seller) { User.create!(name: "Seller", login: "seller-one", password: "seller-password") }
  let(:operator) { User.create!(name: "Operator", login: "operator-one", password: "operator-password", role: "operator") }

  def sign_in(actor, password)
    post "/api/v1/session", params: { session: { login: actor.login, password: password } },
      headers: { "X-Hammerfall-Login" => "1" }, as: :json
    expect(response).to have_http_status(:created)
    @csrf = json.fetch("csrf_token")
  end

  def command_headers(key = SecureRandom.uuid)
    { "X-CSRF-Token" => @csrf, "Idempotency-Key" => key }
  end

  it "authenticates, expires, revokes, and never exposes credentials" do
    post "/api/v1/session", params: { session: { login: buyer.login, password: "buyer-password" } }, as: :json
    expect(response).to have_http_status(:bad_request)
    post "/api/v1/session", params: { session: { login: buyer.login, password: "wrong" } },
      headers: { "X-Hammerfall-Login" => "1" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    sign_in(buyer, "buyer-password")
    expect(response.body).not_to include("password_digest", "buyer-password", "hammerfall_session")
    get "/api/v1/session"
    expect(json.dig("data", "id")).to eq(buyer.id)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    UserSession.update_all(created_at: 1.day.ago, expires_at: 1.minute.ago)
    get "/api/v1/session"
    expect(response).to have_http_status(:unauthorized)
    sign_in(buyer, "buyer-password")
    delete "/api/v1/session", headers: { "X-CSRF-Token" => @csrf }
    expect(response).to have_http_status(:no_content)
    get "/api/v1/session"
    expect(response).to have_http_status(:unauthorized)
  end

  it "never authenticates an uncredentialed legacy user against the dummy bcrypt digest" do
    legacy = User.create!(name: "Legacy without credentials")
    allow(User).to receive(:find_by).and_return(legacy)
    post "/api/v1/session", params: { session: { login: "legacy-dummy", password: "no-such-user" } },
      headers: { "X-Hammerfall-Login" => "1" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("invalid_credentials")
    expect(UserSession.where(user: legacy)).to be_empty
  end

  it "replaces the existing session credential on login and revokes its old row" do
    sign_in(buyer, "buyer-password")
    first_cookie = response.headers.fetch("Set-Cookie")
    first_session_id = UserSession.find_by!(user: buyer).id

    sign_in(buyer, "buyer-password")
    expect(response.headers.fetch("Set-Cookie")).not_to eq(first_cookie)
    expect(UserSession.where(id: first_session_id)).to be_empty
    expect(UserSession.where(user: buyer).count).to eq(1)
    get "/api/v1/session"
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "id")).to eq(buyer.id)
  end

  it "derives bid ownership from session, rejects impersonation and preserves same-actor replay" do
    auction = create_auction(state: "active", seller: seller)
    path = "/api/v1/auctions/#{auction.id}/bids"
    post path, params: { bid: { amount: 10_000 } }, headers: { "Idempotency-Key" => "one" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    sign_in(buyer, "buyer-password")
    post path, params: { bid: { bidder_id: seller.id, amount: 10_000 } }, headers: command_headers("one"), as: :json
    expect(response).to have_http_status(:bad_request)
    key = SecureRandom.uuid
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response).to have_http_status(:created)
    original = json
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json).to eq(original)
    delete "/api/v1/session", headers: { "X-CSRF-Token" => @csrf }
    sign_in(seller, "seller-password")
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("seller_self_bid")
    expect(auction.bids.count).to eq(1)
    sign_in(buyer, "buyer-password")
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json).to eq(original)
  end

  it "requires reauthentication after a committed response is lost, then replays the same historical outcome" do
    auction = create_auction(state: "active", seller: seller)
    path = "/api/v1/auctions/#{auction.id}/bids"
    sign_in(buyer, "buyer-password")
    key = SecureRandom.uuid
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response).to have_http_status(:created)
    original = json
    UserSession.update_all(created_at: 1.day.ago, expires_at: 1.minute.ago)
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(auction.bids.count).to eq(1)
    sign_in(buyer, "buyer-password")
    post path, params: { bid: { amount: 10_000 } }, headers: command_headers(key), as: :json
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json).to eq(original)
    expect(auction.bids.count).to eq(1)
  end

  it "replays a retained pre-auth command using the authenticated actor scope" do
    auction = create_auction(state: "active", seller: seller)
    key = SecureRandom.uuid
    original = IdempotentBidding.call(key: key, actor_id: buyer.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000)
    sign_in(buyer, "buyer-password")
    post "/api/v1/auctions/#{auction.id}/bids", params: { bid: { amount: 10_000 } },
      headers: command_headers(key), as: :json
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json).to eq(original.body)
    expect(auction.bids.count).to eq(1)
  end

  it "keeps owner and operator actions distinct and protects CSRF" do
    auction = create_auction(seller: seller)
    sign_in(buyer, "buyer-password")
    patch "/api/v1/auctions/#{auction.id}", params: { auction: { title: "Attack" } }, headers: { "X-CSRF-Token" => @csrf }, as: :json
    expect(response).to have_http_status(:forbidden)
    post "/api/v1/auctions/#{auction.id}/schedule", headers: { "X-CSRF-Token" => @csrf }
    expect(response).to have_http_status(:forbidden)
    post "/api/v1/auctions", params: { auction: auction_attributes }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(json.dig("error", "code")).to eq("invalid_csrf")
    sign_in(seller, "seller-password")
    patch "/api/v1/auctions/#{auction.id}", params: { auction: { title: "Owner edit" } }, headers: { "X-CSRF-Token" => @csrf }, as: :json
    expect(response).to have_http_status(:ok)
    sign_in(operator, "operator-password")
    post "/api/v1/auctions/#{auction.id}/schedule", headers: { "X-CSRF-Token" => @csrf }
    expect(response).to have_http_status(:ok)
  end

  it "rejects seller maximums without creating a private instruction" do
    auction = create_auction(state: "active", seller: seller)
    sign_in(seller, "seller-password")
    put "/api/v1/auctions/#{auction.id}/maximum-bid", params: { maximum_bid: { maximum_amount: 20_000 } },
      headers: command_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("seller_self_bid")
    expect(auction.maximum_bids.count).to eq(0)
  end

  it "keeps seller ownership immutable through ordinary model updates" do
    auction = create_auction(seller: seller)
    expect { auction.update!(seller: buyer) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(auction.reload.seller).to eq(seller)
  end

  it "filters login credentials and session material from ordinary logs" do
    stream = StringIO.new
    logger = ActiveSupport::Logger.new(stream)
    previous = [ Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger ]
    begin
      Rails.logger = ActiveRecord::Base.logger = ActionController::Base.logger = logger
      sign_in(buyer, "buyer-password")
      expect(response).to have_http_status(:created)
      ActiveSupport::LogSubscriber.flush_all!
      cookie_value = response.headers.fetch("Set-Cookie").split(";", 2).first.split("=", 2).last
      [ "buyer-password", buyer.password_digest, cookie_value ].each do |secret|
        expect(stream.string).not_to include(secret)
      end
    ensure
      Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger = previous
    end
  end
end
