require "rails_helper"

RSpec.describe "Application liveness", type: :request do
  it "reports a successful Rails boot" do
    get "/up"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
  end
end
