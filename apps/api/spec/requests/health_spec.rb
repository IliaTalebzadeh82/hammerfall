require "rails_helper"

RSpec.describe "Application liveness", type: :request do
  it "reports a successful Rails boot" do
    get "/up"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
  end

  it "reports database readiness independently of process liveness" do
    get "/ready"
    expect(response).to have_http_status(:ok)

    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection)
      .and_raise(ActiveRecord::ConnectionNotEstablished)
    get "/ready"
    expect(response).to have_http_status(:service_unavailable)
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
