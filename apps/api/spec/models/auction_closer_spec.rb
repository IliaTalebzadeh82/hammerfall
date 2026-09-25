require "rails_helper"

RSpec.describe AuctionCloser do
  it "discovers bounded due candidates in deadline order and finalizes through the domain" do
    due = Array.new(3) { expire_fixture(create_auction(state: "active")) }
    open = create_auction(state: "active")
    closer = described_class.new(batch_size: 2)
    expect(closer.candidate_ids).to eq(due.first(2).map(&:id))
    closer.run_once
    expect(due.map { |a| a.reload.status }).to eq(%w[closed closed active])
    closer.run_once
    expect(due.last.reload.status).to eq("closed")
    expect(open.reload.status).to eq("active")
  end

  it "skips discovery work after shutdown is requested" do
    closer = described_class.new
    closer.stop
    expect(closer).not_to receive(:run_once)
    closer.run(once: true)
  end

  [ { interval: 0 }, { interval: -1 }, { interval: "NaN" }, { batch_size: 0 }, { batch_size: 10_001 } ].each do |options|
    it "rejects invalid process configuration #{options}" do
      expect { described_class.new(**options) }.to raise_error(ArgumentError)
    end
  end

  it "logs a transient per-auction failure and still processes the rest of the batch" do
    first, second = Array.new(2) { expire_fixture(create_auction(state: "active")) }
    logger = instance_double(ActiveSupport::Logger)
    closer = described_class.new(logger: logger)
    allow(Auction).to receive(:find).and_call_original
    allow(Auction).to receive(:find).with(first.id).and_raise(ActiveRecord::LockWaitTimeout)
    expect(logger).to receive(:warn).with("auction_closer retry auction_id=#{first.id} error=ActiveRecord::LockWaitTimeout")
    expect(closer.run_once).to eq(1)
    expect(first.reload.status).to eq("active")
    expect(second.reload.status).to eq("closed")
  end

  it "logs the auction ID and propagates an unknown failure" do
    auction = expire_fixture(create_auction(state: "active"))
    logger = instance_double(ActiveSupport::Logger)
    closer = described_class.new(logger: logger)
    allow(Auction).to receive(:find).with(auction.id).and_raise(RuntimeError, "unexpected")
    expect(logger).to receive(:error).with("auction_closer failure auction_id=#{auction.id} error=RuntimeError")
    expect { closer.run_once }.to raise_error(RuntimeError, "unexpected")
  end

  it "reports an incomplete one-shot sweep as failure" do
    closer = described_class.new
    allow(closer).to receive(:run_once).and_return(1)
    expect { closer.run(once: true) }.to raise_error(AuctionCloser::SweepIncomplete)
  end

  it "skips a candidate cancelled between discovery and finalization" do
    auction = expire_fixture(create_auction(state: "active"))
    closer = described_class.new
    allow(closer).to receive(:candidate_ids).and_return([ auction.id ])
    auction.cancel!
    expect(closer.run_once).to eq(0)
    expect(auction.reload.status).to eq("cancelled")
  end
end
