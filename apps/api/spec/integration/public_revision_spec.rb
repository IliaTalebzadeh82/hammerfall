require "rails_helper"
require_relative "../support/committed_auction_context"

RSpec.describe "Committed public auction changes", type: :model do
  self.use_transactional_tests = false
  include_context "committed auction concurrency"

  def messages(auction)
    ActionCable.server.pubsub.broadcasts(AuctionPublication.stream(auction.id)).map { |raw| JSON.parse(raw) }
  end

  def clear(auction)
    ActionCable.server.pubsub.clear_messages(AuctionPublication.stream(auction.id))
  end

  it "counts public edits and lifecycle changes, but not unchanged or duplicate operations" do
    auction = active_auction
    expect(auction.public_revision).to eq(2) # schedule, activate; creation is zero
    clear(auction)
    expect { auction.activate!; auction.close! }.not_to change { auction.reload.public_revision }
    auction.cancel!
    auction.cancel!
    expect(auction.reload.public_revision).to eq(3)
    expect(messages(auction)).to eq([ { "type" => "auction.changed.v1", "auction_id" => auction.id, "revision" => 3 } ])
    draft = create_auction
    @auction_ids << draft.id
    draft.edit_draft!(title: "Changed")
    expect(draft.public_revision).to eq(1)
    draft.edit_draft!(title: "Changed")
    expect(draft.public_revision).to eq(1)
    expect(messages(draft).size).to eq(1)
    expect { draft.update!(title: "Bypass") }.to raise_error(ActiveRecord::RecordInvalid)
    expect { draft.reload.update!(public_revision: 99) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "increments once for a manual bid and one whole two-row proxy contest plus extension" do
    auction = active_auction(minimum_increment: 1000)
    auction.set_maximum!(bidder: @bidder, maximum_amount: 987_654)
    other = User.create!(name: "Challenger")
    @user_ids << other.id
    deadline_fixture(auction, AuctionClock.now + 30)
    before = auction.public_revision
    old_end = auction.ends_at
    clear(auction)
    auction.place_bid!(bidder: other, amount: 20_000)
    expect(auction.reload).to have_attributes(public_revision: before + 1, ends_at: old_end + 90, current_price: 21_000)
    expect(auction.bids.order(:sequence).pluck(:amount)).to eq([ 10_000, 20_000, 21_000 ])
    expect(messages(auction)).to eq([ { "type" => "auction.changed.v1", "auction_id" => auction.id, "revision" => before + 1 } ])
    expect(messages(auction).to_json.bytesize).to be < 150
  end

  it "reveals nothing for private-only increases or identical maxima, but publishes protection-only extension" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    before = auction.reload.attributes
    clear(auction)
    [ 30_000, 50_000, 50_000 ].each { |amount| auction.set_maximum!(bidder: @bidder, maximum_amount: amount) }
    expect(auction.reload.attributes).to eq(before)
    expect(messages(auction)).to be_empty
    deadline_fixture(auction, AuctionClock.now + 30)
    old_end = auction.ends_at
    auction.set_maximum!(bidder: @bidder, maximum_amount: 60_000)
    expect(auction.reload).to have_attributes(public_revision: before["public_revision"] + 1, ends_at: old_end + 90)
    expect(auction.bids.count).to eq(1)
    expect(messages(auction).size).to eq(1)
  end

  it "does not publish until the outermost commit and independent readers can then see the revision" do
    auction = active_auction
    clear(auction)
    before = auction.public_revision
    observed = []
    allow(AuctionPublication).to receive(:publish).and_wrap_original do |original, id, revision|
      observed << result(worker { Auction.find(id).public_revision })
      original.call(id, revision)
    end
    ApplicationRecord.transaction do
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expect(messages(auction)).to be_empty
      expect(observed).to be_empty
      expect(result(worker { Auction.find(auction.id).public_revision })).to eq(before)
    end
    expect(observed).to eq([ before + 1 ])
    expect(messages(auction).size).to eq(1)
  end

  it "rolls back domain state, revision and notification after a released domain savepoint" do
    auction = active_auction
    clear(auction)
    before = auction.attributes
    ApplicationRecord.transaction do
      auction.place_bid!(bidder: @bidder, amount: 10_000)
      expect(auction.public_revision).to eq(before["public_revision"] + 1)
      raise ActiveRecord::Rollback
    end
    expect(auction.reload.attributes).to eq(before)
    expect(auction.bids).to be_empty
    expect(messages(auction)).to be_empty
  end

  it "discards a failed savepoint's notification even if the caller commits other work" do
    auction = active_auction
    clear(auction)
    before = auction.public_revision
    ApplicationRecord.transaction do
      ApplicationRecord.transaction(requires_new: true) do
        auction.place_bid!(bidder: @bidder, amount: 10_000)
        raise ActiveRecord::Rollback
      end
      auction.place_bid!(bidder: @bidder, amount: 11_000)
    end
    expect(auction.reload.public_revision).to eq(before + 1)
    expect(messages(auction).size).to eq(1)
    expect(auction.bids.pluck(:amount)).to eq([ 11_000 ])
  end

  it "does not increment or notify on replay, rejection or pruning" do
    auction = active_auction
    command = -> { IdempotentBidding.call(key: "private-key", actor_id: @bidder.id, auction_id: auction.id, operation: "place_bid", amount: 10_000) }
    command.call
    clear(auction)
    before = auction.reload.attributes
    expect(command.call.replayed).to be(true)
    expect { auction.place_bid!(bidder: @bidder, amount: 9999) }.to raise_error(DomainError)
    IdempotencyRecord.prune_expired!
    expect(auction.reload.attributes).to eq(before)
    expect(messages(auction)).to be_empty
  end

  it "does not republish an accepted maximum when its idempotent result is replayed" do
    auction = active_auction
    command = -> { IdempotentBidding.call(key: "maximum-replay", actor_id: @bidder.id, auction_id: auction.id, operation: "set_maximum_bid", amount: 30_000) }
    expect(command.call.status).to eq(200)
    expect(auction.reload.public_revision).to eq(3)
    clear(auction)
    before = auction.attributes
    expect(command.call.replayed).to be(true)
    expect(auction.reload.attributes).to eq(before)
    expect(messages(auction)).to be_empty
  end

  it "finalizes one winner and one revision across duplicate closers" do
    auction = active_auction
    auction.place_bid!(bidder: @bidder, amount: 10_000)
    expire_fixture(auction)
    before = auction.public_revision
    clear(auction)
    threads = Array.new(4) { worker { Auction.find(auction.id).close! } }
    threads.each { |thread| result(thread) }
    expect(auction.reload).to have_attributes(status: "closed", winner_id: @bidder.id, public_revision: before + 1)
    expect(messages(auction).size).to eq(1)
  end

  it "keeps a committed idempotent success when Cable publication fails" do
    auction = active_auction
    allow(ActionCable.server).to receive(:broadcast).and_raise(IOError, "transport failed")
    result = IdempotentBidding.call(key: "lost-broadcast", actor_id: @bidder.id, auction_id: auction.id, operation: "place_bid", amount: 10_000)
    expect(result.status).to eq(201)
    expect(auction.reload.public_revision).to eq(3)
    expect(auction.bids.count).to eq(1)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).first.status).to eq("completed")
  end

  it "keeps a committed idempotent success when Redis enqueue fails" do
    auction = active_auction
    allow(AuctionChangedJob).to receive(:perform_async).and_raise(IOError, "queue unavailable")
    result = IdempotentBidding.call(key: "lost-enqueue", actor_id: @bidder.id, auction_id: auction.id, operation: "place_bid", amount: 10_000)
    expect(result.status).to eq(201)
    expect(auction.reload).to have_attributes(public_revision: 3, current_price: 10_000)
    expect(auction.bids.count).to eq(1)
    expect(IdempotencyRecord.where(actor_id: @bidder.id).first.status).to eq("completed")
  end
end
