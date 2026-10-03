require "rails_helper"
require "tempfile"

RSpec.describe Idempotency::Keyring do
  it "rejects a missing production file and weak or malformed key material" do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect { described_class.load!(env: {}) }.to raise_error(ArgumentError, /must name a readable file/)
    Tempfile.create("keyring") do |file|
      file.write(JSON.generate(current: "v1", keys: { "v1" => "a" * 64 }))
      file.flush
      expect { described_class.load!(env: { "IDEMPOTENCY_HMAC_KEYRING_FILE" => file.path }) }
        .to raise_error(ArgumentError, /key quality/)
    end
  end

  it "loads a current key and a previous key from a file without exposing material" do
    keys = { "v1" => Digest::SHA256.hexdigest("first local test secret"),
      "v2" => Digest::SHA256.hexdigest("second local test secret") }
    Tempfile.create("keyring") do |file|
      file.write(JSON.generate(current: "v2", keys: keys))
      file.flush
      ring = described_class.load!(env: { "IDEMPOTENCY_HMAC_KEYRING_FILE" => file.path })
      expect(ring.current_id).to eq("v2")
      expect(ring.lookup_scopes(actor_id: 1, operation: "place_bid", key: "opaque").length).to eq(2)
      expect(ring.digest("opaque", "v1")).not_to eq(ring.digest("opaque", "v2"))
    end
  end
end
