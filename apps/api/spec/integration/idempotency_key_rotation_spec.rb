require "rails_helper"

RSpec.describe "Idempotency digest rotation", type: :model do
  let(:actor) { User.create!(name: "Rotation actor") }
  let(:other) { User.create!(name: "Other rotation actor") }
  let(:auction) { create_auction(state: "active") }
  let(:old_secret) { Digest::SHA256.hexdigest("old rotation test key with explicit local scope") }
  let(:new_secret) { Digest::SHA256.hexdigest("new rotation test key with explicit local scope") }
  let(:old_ring) { Idempotency::Keyring.new(current_id: "old", keys: { "old" => old_secret }) }
  let(:rotated_ring) do
    Idempotency::Keyring.new(current_id: "new", keys: { "old" => old_secret, "new" => new_secret })
  end

  def command(key, who: actor, amount: 10_000)
    IdempotentBidding.call(key: key, actor_id: who.id, auction_id: auction.id,
      operation: "place_bid", amount: amount)
  end

  it "writes only the current version, replays through rotation and preserves conflict and actor scope" do
    allow(Idempotency::Keyring).to receive(:current).and_return(old_ring)
    original = command("rotation-key")
    old = IdempotencyRecord.find_by!(actor_id: actor.id)
    expect(old).to have_attributes(digest_version: 2, digest_key_id: "old",
      key_digest: old_ring.digest("rotation-key", "old"))

    allow(Idempotency::Keyring).to receive(:current).and_return(rotated_ring)
    expect(command("rotation-key")).to have_attributes(status: 201, body: original.body, replayed: true)
    expect(command("rotation-key", amount: 12_000).status).to eq(409)
    expect(command("rotation-key", who: other, amount: 12_000).replayed).to be(false)
    command("fresh-key", amount: 13_000)
    fresh = IdempotencyRecord.find_by!(actor_id: actor.id, digest_key_id: "new")
    expect(fresh.key_digest).to eq(rotated_ring.digest("fresh-key", "new"))
    expect(IdempotencyRecord.where(actor_id: actor.id).count).to eq(2)
  end

  it "rejects early retirement while old-key rows remain, even after expiry" do
    allow(Idempotency::Keyring).to receive(:current).and_return(old_ring)
    command("kept-key")
    IdempotencyRecord.where(actor_id: actor.id).update_all("created_at = CURRENT_TIMESTAMP - INTERVAL '9 days', expires_at = CURRENT_TIMESTAMP - INTERVAL '1 day'")
    new_only = Idempotency::Keyring.new(current_id: "new", keys: { "new" => new_secret })
    allow(Idempotency::Keyring).to receive(:current).and_return(new_only)
    expect { command("another-key", amount: 12_000) }.to raise_error(ArgumentError, /omits retained key IDs/)
    expect(IdempotencyRecord.where(actor_id: actor.id).count).to eq(1)
  end

  it "replays retained legacy SHA rows and still detects changed payloads" do
    original = command("legacy-key")
    IdempotencyRecord.where(actor_id: actor.id).update_all(
      key_digest: Digest::SHA256.hexdigest("legacy-key"), digest_version: 1, digest_key_id: nil
    )
    record = IdempotencyRecord.find_by!(actor_id: actor.id)
    expect(record.digest_version).to eq(1)
    expect(command("legacy-key")).to have_attributes(status: 201, body: original.body, replayed: true)
    expect(command("legacy-key", amount: 12_000).status).to eq(409)
    expect(IdempotencyRecord.where(actor_id: actor.id).count).to eq(1)
  end
end
