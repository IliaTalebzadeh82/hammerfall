require "rails_helper"

RSpec.describe "Idempotency SQL integrity" do
  let(:actor) { User.create!(name: "Actor") }
  let(:row) do
    { actor_id: actor.id, operation: "place_bid", key_digest: "a" * 64, request_fingerprint: "b" * 64,
      status: "completed", response_status: 201, response_body: { data: { id: 1 } }, expires_at: AuctionClock.now + 7.days }
  end

  it "enforces actor/operation/key uniqueness and the actor foreign key" do
    IdempotencyRecord.insert_all!([ row ])
    expect do
      ApplicationRecord.transaction(requires_new: true) { IdempotencyRecord.insert_all!([ row ]) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect do
      ApplicationRecord.transaction(requires_new: true) { IdempotencyRecord.insert_all!([ row.merge(actor_id: -1) ]) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    IdempotencyRecord.insert_all!([ row.merge(operation: "set_maximum_bid") ])
    expect(IdempotencyRecord.count).to eq(2)
  end

  [ { actor_id: nil }, { operation: "typo" }, { key_digest: "bad" }, { request_fingerprint: nil },
    { status: "zombie" }, { response_status: 500 }, { response_status: nil }, { response_body: [] },
    { response_body: nil }, { status: "processing" }, { expires_at: nil }, { expires_at: Time.utc(2000) } ].each do |change|
    it "rejects invalid stored outcome #{change}" do
      valid = row
      expect do
        ApplicationRecord.transaction(requires_new: true) { IdempotencyRecord.insert_all!([ valid.merge(change) ]) }
      end.to raise_error(ActiveRecord::StatementInvalid) { |error| expect(error.cause).to be_a(PG::CheckViolation).or be_a(PG::NotNullViolation) }
    end
  end
end
