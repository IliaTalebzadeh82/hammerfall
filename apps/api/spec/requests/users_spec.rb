require "rails_helper"

RSpec.describe "Public identity directory", :domain, type: :request do
  it "lists only public bidders and minimal display fields" do
    user = User.create!(name: "Alice", login: "alice-one", password: "private-password")
    User.create!(name: "Never bid", login: "never-bid", password: "private-password")
    auction = create_auction(state: "active")
    auction.place_bid!(bidder: user, amount: 10_000)
    get "/api/v1/users"
    expect(json.fetch("data")).to eq([ { "id" => user.id, "name" => "Alice" } ])
    expect(response.body).not_to include("login", "password", "role")
  end

  it "does not allow anonymous account creation" do
    post "/api/v1/users", params: { user: { name: "Attacker" } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(User.count).to eq(0)
  end
end
