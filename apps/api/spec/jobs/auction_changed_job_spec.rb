require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe AuctionChangedJob do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"
  it "broadcasts only a current public hint for duplicate and reordered jobs" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    current = auction.reload.public_revision
    stream = AuctionPublication.stream(auction.id)
    ActionCable.server.pubsub.clear_messages(stream)

    described_class.new.perform(auction.id, current - 1)
    described_class.new.perform(auction.id, current)

    messages = ActionCable.server.pubsub.broadcasts(stream).map { |raw| JSON.parse(raw) }
    expect(messages).to eq(Array.new(2) { { "type" => "auction.changed.v1", "auction_id" => auction.id, "revision" => current } })
    expect(messages.to_json).not_to include("maximum_amount", "priority_sequence", "origin", "idempotency")
  end

  it "does not resurrect deleted auctions or accept a regressed revision" do
    expect { described_class.new.perform(9_000_000, 1) }.not_to raise_error
    auction = active_auction
    expect { described_class.new.perform(auction.id, auction.public_revision + 1) }.to raise_error("public revision regressed")
  end

  it "lets transport failure reach Sidekiq retry instead of changing auction state" do
    auction = active_auction
    before = auction.reload.attributes
    allow(ActionCable.server).to receive(:broadcast).and_raise(IOError, "socket unavailable")
    expect { described_class.new.perform(auction.id, auction.public_revision) }.to raise_error(IOError)
    expect(auction.reload.attributes).to eq(before)
    expect(described_class.sidekiq_options_hash["retry"]).to eq(5)
  end

  it "queues only the public auction ID and revision after commit" do
    auction = active_auction
    Sidekiq.testing!(:fake) do
      described_class.clear
      auction.set_maximum!(bidder: @bidder, maximum_amount: 30_000)
      expect(described_class.jobs.size).to eq(1)
      expect(described_class.jobs.first.fetch("args")).to eq([ auction.id, auction.public_revision ])
      expect(described_class.jobs.first.to_json).not_to include("maximum_amount", "priority_sequence", "origin")
    ensure
      described_class.clear
    end
  end
end
