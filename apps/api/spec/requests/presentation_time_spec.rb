require "rails_helper"

RSpec.describe "API presentation time", type: :request do
  it "provides fresh application time on reads without changing the representation" do
    get "/api/v1/users"
    expect(response).to have_http_status(:ok)
    expect(Time.iso8601(response.headers.fetch("X-Server-Time"))).to be_within(2.seconds).of(Time.current)
    expect(JSON.parse(response.body).keys).to contain_exactly("data", "meta")
  end

  it "provides presentation time on expected errors too" do
    post "/api/v1/auctions/1/bids", params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(Time.iso8601(response.headers.fetch("X-Server-Time"))).to be_within(2.seconds).of(Time.current)
  end
end
