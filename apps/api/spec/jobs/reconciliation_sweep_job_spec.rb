require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe ReconciliationSweepJob do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"
  it "reports drift read-only and remains safe to run twice" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    before = auction.reload.attributes
    errors = []
    allow(Rails.logger).to receive(:error) { |message| errors << message }
    2.times { described_class.new.perform(auction.id - 1, auction.id) }
    expect(errors).to be_empty
    expect(auction.reload.attributes).to eq(before)

    # Simulate privileged corruption, without exposing private data in logs.
    Auction.where(id: auction.id).update_all(current_price: 11_000)
    2.times { described_class.new.perform(auction.id - 1, auction.id) }
    expect(errors).to eq(Array.new(2, "auction_reconciliation drift auction_id=#{auction.id} kind=postgresql_state"))
    expect(auction.reload.current_price).to eq(11_000)
  end

  it "can be scheduled repeatedly without modifying authoritative records" do
    auction = active_auction
    before = auction.reload.attributes
    Sidekiq.testing!(:fake) do
      described_class.clear
      scheduler = ReconciliationScheduler.new(interval: 5)
      2.times { scheduler.run_once }
      expect(described_class.jobs.length).to eq(2)
      described_class.jobs.each { |job| expect(job.fetch("args")).to eq([]) }
    ensure
      described_class.clear
    end
    expect(auction.reload.attributes).to eq(before)
  end

  it "scans beyond one bounded batch without repairing a later drift" do
    auctions = Array.new(described_class::BATCH_SIZE + 1) { create_auction }
    @auction_ids.concat(auctions.map(&:id))
    last = auctions.last
    Auction.where(id: last.id).update_all(current_price: 11_000)
    expect(Rails.logger).to receive(:error).once.with("auction_reconciliation drift auction_id=#{last.id} kind=postgresql_state")
    described_class.new.perform(auctions.first.id - 1, last.id)
    expect(last.reload.current_price).to eq(11_000)
  end

  it "does not hide scheduler enqueue failure and validates cadence" do
    expect { ReconciliationScheduler.new(interval: 0) }.to raise_error(ArgumentError)
    scheduler = ReconciliationScheduler.new(interval: 5)
    allow(described_class).to receive(:perform_async).and_raise(IOError)
    expect { scheduler.run(once: true) }.to raise_error(IOError)
  end
end
