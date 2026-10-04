require "rails_helper"
require "stringio"

RSpec.describe "Idempotent bidding API", type: :request do
  let(:auction) { create_auction(state: "active", minimum_increment: 1_000) }
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }
  let(:path) { "/api/v1/auctions/#{auction.id}/bids" }
  let(:key) { "opaque-command:abc-123" }

  def bid(amount = 10_000, key_value: key, user: alice, target: path)
    sign_in_as(user)
    headers = key_value.nil? ? auth_headers : auth_headers("Idempotency-Key" => key_value)
    post target, params: { bid: { amount: amount } }, headers: headers, as: :json
  end

  def maximum(amount = 30_000, key_value: key)
    sign_in_as(alice)
    put "/api/v1/auctions/#{auction.id}/maximum-bid", params: { maximum_bid: { maximum_amount: amount } },
      headers: auth_headers("Idempotency-Key" => key_value), as: :json
  end

  [ nil, "", " ", "has spaces", "x" * 256, "é", "line\nbreak" ].each do |value|
    it "rejects missing or malformed key #{value.inspect} before mutation" do
      bid(key_value: value)
      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq(value.nil? ? "idempotency_key_required" : "invalid_idempotency_key")
      expect(auction.bids).to be_empty
      expect(IdempotencyRecord.count).to eq(0)
    end
  end

  it "accepts the maximum key length and replays exact status/body and original bid identity" do
    bid(key_value: "x" * 255)
    original = response.body
    expect(response.status).to eq(201)
    expect(response.headers["Idempotency-Replayed"]).to be_nil
    bid(key_value: "x" * 255)
    expect(response.status).to eq(201)
    expect(response.body).to eq(original)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(auction.bids.count).to eq(1)
    expect(IdempotencyRecord.count).to eq(1)
    expect(json.dig("data", "sequence")).to eq(1)
  end

  it "rolls back the whole command at the chaos boundary before commit" do
    auction
    baseline = OutboxEvent.where(auction_id: auction.id).count
    baseline_revision = auction.public_revision
    allow(ChaosCrash).to receive(:at_command!) do |boundary, auction_id|
      expect(auction_id).to eq(auction.id)
      raise Interrupt, "simulated process death" if boundary == "command_before_commit"
    end
    expect { IdempotentBidding.call(key: key, actor_id: alice.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000) }.to raise_error(Interrupt, "simulated process death")
    expect(auction.reload.bids.count).to eq(0)
    expect(auction.public_revision).to eq(baseline_revision)
    expect(OutboxEvent.where(auction_id: auction.id).count).to eq(baseline)
    expect(IdempotencyRecord.count).to eq(0)
    allow(ChaosCrash).to receive(:at_command!).and_call_original
    expect(IdempotentBidding.call(key: key, actor_id: alice.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000).replayed).to be(false)
    expect(auction.reload.bids.count).to eq(1)
  end

  it "keeps the committed outcome when the chaos boundary drops the response" do
    auction
    allow(ChaosCrash).to receive(:at_command!) do |boundary, auction_id|
      expect(auction_id).to eq(auction.id)
      raise Interrupt, "simulated process death" if boundary == "command_committed"
    end
    expect { IdempotentBidding.call(key: key, actor_id: alice.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000) }.to raise_error(Interrupt, "simulated process death")
    expect(auction.reload.bids.count).to eq(1)
    expect(IdempotencyRecord.where(actor_id: alice.id, status: "completed").count).to eq(1)
    allow(ChaosCrash).to receive(:at_command!).and_call_original
    outcome = IdempotentBidding.call(key: key, actor_id: alice.id, auction_id: auction.id,
      operation: "place_bid", amount: 10_000)
    expect(outcome.replayed).to be(true)
    expect(auction.reload.bids.count).to eq(1)
  end

  it "canonicalizes semantic input independently of JSON order, whitespace, and unrelated headers" do
    bid
    original = response.body
    post path, params: ' { "bid": { "amount" : 10000 } } ',
      headers: auth_headers("Content-Type" => "application/json", "Idempotency-Key" => key, "X-Unrelated" => "changed")
    expect(response.body).to eq(original)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    bid(10_000.0)
    expect(response.status).to eq(409) # Float input is not a valid integer-money command.
  end

  it "conflicts on changed amount or auction without disclosing prior request data" do
    bid
    bid(12_000)
    expect(response.status).to eq(409)
    expect(json.dig("error", "code")).to eq("idempotency_key_conflict")
    other = create_auction(state: "active")
    bid(target: "/api/v1/auctions/#{other.id}/bids")
    expect(response.status).to eq(409)
    expect(other.bids).to be_empty
    expect(auction.bids.count).to eq(1)
  end

  it "scopes keys by actor and operation rather than auction or payload values" do
    bid
    bid(12_000, user: bob)
    expect(response.status).to eq(201)
    maximum
    expect(response.status).to eq(200)
    expect(IdempotencyRecord.count).to eq(3)
  end

  it "replays a lost successful bid after price/leader changes and then closure" do
    bid
    lost_response = response.body
    bid(50_000, key_value: "other-command", user: bob)
    before = auction.reload.attributes
    bid
    expect(response.body).to eq(lost_response)
    expect(auction.reload.attributes).to eq(before)
    expire_fixture(auction).close!
    closed = auction.reload.attributes
    bid
    expect(response.status).to eq(201)
    expect(response.body).to eq(lost_response)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(auction.reload.attributes).to eq(closed)
    expect(auction.bids.count).to eq(2)
  end

  it "replays maximum success after closure without reevaluating its now-invalid ceiling" do
    maximum
    original = response.body
    auction.place_bid!(bidder: bob, amount: 50_000)
    expire_fixture(auction).close!
    before = auction.maximum_bids.first.attributes
    maximum
    expect(response.status).to eq(200)
    expect(response.body).to eq(original)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(auction.maximum_bids.first.attributes).to eq(before)
  end

  it "preserves original domain rejections after state and minimum change" do
    bid(9_999)
    rejection = response.body
    expect(response.status).to eq(422)
    auction.place_bid!(bidder: bob, amount: 50_000)
    bid(9_999)
    expect(response.status).to eq(422)
    expect(response.body).to eq(rejection)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(json.dig("error", "details", "minimum_bid")).to eq(10_000)
  end

  it "replays a stepped-minimum rejection after the price crosses a band" do
    stepped = create_auction(state: "active", increment_policy: "stepped", starting_price: 10_000)
    stepped.place_bid!(bidder: bob, amount: 10_000)
    bid(10_499, target: "/api/v1/auctions/#{stepped.id}/bids")
    original = response.body
    expect(response.status).to eq(422)
    expect(json.dig("error", "details", "minimum_bid")).to eq(10_500)
    stepped.place_bid!(bidder: bob, amount: 20_001)
    bid(10_499, target: "/api/v1/auctions/#{stepped.id}/bids")
    expect(response.body).to eq(original)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(stepped.reload.current_price).to eq(20_001)
  end

  it "persists expired, decrease, validation and missing-auction terminal outcomes" do
    maximum
    maximum(20_000, key_value: "decrease")
    decreased = response.body
    maximum(20_000, key_value: "decrease")
    expect(response.body).to eq(decreased)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    bid("bad", key_value: "invalid-money")
    expect(response.status).to eq(422)
    expect(IdempotencyRecord.last.response_body.dig("error", "code")).to eq("validation_failed")
    bid(target: "/api/v1/auctions/9223372036854775807/bids", key_value: "missing-auction")
    expect(response.status).to eq(404)
    expire_fixture(auction)
    bid(key_value: "late")
    expired = response.body
    auction.close!
    bid(key_value: "late")
    expect(response.body).to eq(expired)
    expect(json.dig("error", "code")).to eq("auction_ended")
  end

  it "distinguishes identical maximum with a new key from a replay" do
    maximum
    maximum(key_value: "new-logical-command")
    expect(response.headers["Idempotency-Replayed"]).to be_nil
    expect(IdempotencyRecord.count).to eq(2)
    expect(auction.maximum_bids.first.priority_sequence).to eq(1)
    maximum
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
  end

  it "replays a proxy-generating late bid without another row, price, leader, max or extension write" do
    auction.set_maximum!(bidder: bob, maximum_amount: 30_000)
    deadline_fixture(auction, AuctionClock.now + 30)
    original_end = auction.ends_at
    bid(20_000)
    outcome = response.body
    before = auction.reload.attributes
    maximum_state = auction.maximum_bids.map(&:attributes)
    3.times do
      bid(20_000)
      expect(response.body).to eq(outcome)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
    end
    expect(auction.reload.attributes).to eq(before)
    expect(auction.ends_at).to eq(original_end + 90)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 20_000, 21_000 ])
    expect(auction.maximum_bids.reload.map(&:attributes)).to eq(maximum_state)
  end

  it "stores only public maximum acknowledgement and hashes, never raw key or private payload" do
    stream = StringIO.new
    logger = ActiveSupport::Logger.new(stream)
    previous = [ Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger ]
    begin
      Rails.logger = ActiveRecord::Base.logger = ActionController::Base.logger = logger
      maximum(987_654)
      expect(response.status).to eq(200)
      first = response.body
      maximum(987_654)
      expect(response.body).to eq(first)
      maximum(987_655)
      expect(response.status).to eq(409)
      record = IdempotencyRecord.first
      expect(record.attributes.to_json).not_to include("987654", "987655", key, "maximum_amount", "priority_sequence")
      expect(record.response_body).to eq("data" => { "auction_id" => auction.id, "bidder_id" => alice.id, "accepted" => true })
      expect(record.request_fingerprint).to match(/\A[0-9a-f]{64}\z/)
      ActiveSupport::LogSubscriber.flush_all!
      expect(stream.string).not_to include("987654", "987655", key)
    ensure
      Rails.logger, ActiveRecord::Base.logger, ActionController::Base.logger = previous
    end
  end

  context "with a hidden reserve" do
    let(:auction) { create_auction(state: "active", reserve_price: 50_000, minimum_increment: 1_000) }

    it "replays a below-reserve acceptance and rejection as historical outcomes" do
      bid(20_000)
      accepted = response.body
      expect(response.status).to eq(201)
      bid(20_999, key_value: "reserve-low")
      rejected = response.body
      expect(response.status).to eq(422)
      bid(50_000, key_value: key, user: bob)
      expect(auction.reload.reserve_status).to eq("met")
      bid(20_000)
      expect(response.body).to eq(accepted)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      bid(20_999, key_value: "reserve-low")
      expect(response.body).to eq(rejected)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(auction.bids.count).to eq(2)
    end

    it "replays an above-reserve maximum without recomputing after competition or closure" do
      maximum(70_000)
      accepted = response.body
      expect(auction.reload.current_price).to eq(50_000)
      bid(60_000, key_value: "contest", user: bob)
      expect(auction.reload.current_price).to eq(61_000)
      expire_fixture(auction).close!
      before = auction.reload.attributes
      maximum(70_000)
      expect(response.body).to eq(accepted)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(auction.reload.attributes).to eq(before)
      maximum(71_000)
      expect(json.dig("error", "code")).to eq("idempotency_key_conflict")
      bid(62_000, user: bob)
      expect(json.dig("error", "code")).to eq("invalid_auction_state")
    end
  end
end
