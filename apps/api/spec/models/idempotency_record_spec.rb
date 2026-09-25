require "rails_helper"

RSpec.describe IdempotencyRecord do
  let(:actor) { User.create!(name: "Retention actor") }
  let(:auction) { create_auction(state: "active") }

  def command(key)
    IdempotentBidding.call(key: key, actor_id: actor.id, auction_id: auction.id, operation: "set_maximum_bid", amount: 30_000)
  end

  it "reserves expired records until physical prune, deletes a bounded batch, then permits reuse" do
    3.times { |index| command("key-#{index}") }
    current = described_class.order(:id).last
    expired = described_class.order(:id).first(2)
    described_class.where(id: expired.map(&:id)).update_all("created_at = CURRENT_TIMESTAMP - INTERVAL '9 days', expires_at = CURRENT_TIMESTAMP - INTERVAL '1 day'")
    expect(command("key-0").replayed).to be(true)
    expect(described_class.prune_expired!(batch_size: 1)).to eq(1)
    expect(command("key-0").replayed).to be(false)
    expect(described_class.prune_expired!(batch_size: 100)).to eq(1)
    expect(described_class.exists?(current.id)).to be(true)
    expect(described_class.count).to eq(2)
  end

  it "assigns seven days of DB-clock retention and makes terminal records ordinarily immutable" do
    command("kept")
    record = described_class.first
    expect(record.expires_at - record.created_at).to eq(7.days)
    expect { record.update!(response_status: 422) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "leaves neither auction mutation nor ownership after an unexpected application exception" do
    expect do
      Idempotency::Executor.call(key: "failure", actor_id: actor.id, operation: "place_bid",
        auction_id: auction.id, arguments: { "amount" => 10_000 }) do
        auction.place_bid!(bidder: actor, amount: 10_000)
        raise "Unexpected response-building failure"
      end
    end.to raise_error(RuntimeError, "Unexpected response-building failure")
    expect(described_class.count).to eq(0)
    expect(auction.reload.current_leader_id).to be_nil
    expect(auction.bids).to be_empty
    retry_result = IdempotentBidding.call(key: "failure", actor_id: actor.id, auction_id: auction.id, operation: "place_bid", amount: 10_000)
    expect(retry_result).to have_attributes(status: 201, replayed: false)
  end

  [ 0, -1, 10_001, "bad" ].each do |size|
    it "rejects invalid prune batch #{size}" do
      expect { described_class.prune_expired!(batch_size: size) }.to raise_error(ArgumentError)
    end
  end
end
