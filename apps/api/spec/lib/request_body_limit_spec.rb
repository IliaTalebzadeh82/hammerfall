require "rails_helper"
require "stringio"

RSpec.describe RequestBodyLimit do
  let(:app) { instance_double("Downstream app") }
  let(:middleware) { described_class.new(app) }

  it "rejects declared oversize before reading or calling Rails" do
    input = instance_double(StringIO)
    expect(input).not_to receive(:read)
    expect(app).not_to receive(:call)
    status, _, body = middleware.call("PATH_INFO" => "/api/v1/session", "CONTENT_LENGTH" => "32769", "rack.input" => input)
    expect(status).to eq(413)
    expect(JSON.parse(body.join).dig("error", "code")).to eq("request_too_large")
  end

  it "reads at most limit plus one byte on an unknown-length stream" do
    input = StringIO.new("a" * (described_class::MAX_BYTES + 100))
    expect(app).not_to receive(:call)
    expect(middleware.call("PATH_INFO" => "/api/v1/auctions/1/bids", "rack.input" => input).first).to eq(413)
    expect(input.pos).to eq(described_class::MAX_BYTES + 1)
  end

  it "forwards an exact-boundary body to Rails from a fresh bounded input" do
    input = StringIO.new("a" * described_class::MAX_BYTES)
    expect(app).to receive(:call) do |env|
      expect(env["rack.input"].read.bytesize).to eq(described_class::MAX_BYTES)
      expect(env["CONTENT_LENGTH"]).to eq(described_class::MAX_BYTES.to_s)
      [ 200, {}, [] ]
    end
    expect(middleware.call("PATH_INFO" => "/api/v1/session", "rack.input" => input).first).to eq(200)
  end
end
