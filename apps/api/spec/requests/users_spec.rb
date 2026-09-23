require "rails_helper"

RSpec.describe "Demo identity API", :domain, type: :request do
  it "creates and lists public minimal user identities" do
    post "/api/v1/users", params: { user: { name: "Alice" } }, as: :json
    expect(response).to have_http_status(:created)
    user = json.fetch("data")
    expect(user.keys).to match_array(%w[id name])
    get "/api/v1/users"
    expect(json.fetch("data")).to eq([ user ])
  end

  it "rejects blank names using the common error envelope" do
    post "/api/v1/users", params: { user: { name: " " } }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("validation_failed")
    expect(json.dig("error", "details", "name")).not_to be_empty
  end
end
