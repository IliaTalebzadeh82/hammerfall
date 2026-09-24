require "rails_helper"

RSpec.describe MaximumBid, :domain, type: :model do
  let(:auction) { create_auction(state: "active", minimum_increment: 1_000) }
  let(:alice) { User.create!(name: "Alice") }
  let(:bob) { User.create!(name: "Bob") }

  def maximum(user, amount)
    auction.set_maximum!(bidder: user, maximum_amount: amount)
  end

  def assert_state(amounts, leader)
    rows = auction.bids.order(:sequence)
    expect(rows.pluck(:amount)).to eq(amounts)
    expect(rows.pluck(:sequence)).to eq((1..amounts.size).to_a)
    expect(auction.reload).to have_attributes(current_price: amounts.last, current_leader_id: leader.id, winner_id: nil)
    expect(rows.last.bidder_id).to eq(leader.id)
    rows.where(origin: "automatic").each do |bid|
      expect(bid.amount).to be <= auction.maximum_bids.find_by!(bidder_id: bid.bidder_id).maximum_amount
    end
  end

  it "opens at starting price and stores unused protection privately" do
    record = maximum(alice, 30_000)
    expect(record).to have_attributes(maximum_amount: 30_000, priority_sequence: 1)
    assert_state([ 10_000 ], alice)
  end

  it "adds and increases protection for a manual leader without raising price" do
    auction.place_bid!(bidder: alice, amount: 20_000)
    record = maximum(alice, 30_000)
    maximum(alice, 50_000)
    expect(record.reload).to have_attributes(maximum_amount: 50_000, priority_sequence: 2)
    assert_state([ 20_000 ], alice)
  end

  it "makes a repeated maximum a no-op, forbids decreases and cancellation" do
    record = maximum(alice, 30_000)
    original = record.attributes
    maximum(alice, 30_000)
    expect(record.reload.attributes).to eq(original)
    expect { maximum(alice, 20_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("maximum_bid_cannot_decrease") }
    expect { record.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.update!(maximum_amount: 40_000) }.to raise_error(ActiveRecord::RecordInvalid)
    assert_state([ 10_000 ], alice)
  end

  [
    [ :manual, 20_000, [ 10_000, 20_000, 21_000 ], :alice ],
    [ :manual, 30_000, [ 10_000, 30_000, 30_000 ], :alice ],
    [ :manual, 35_000, [ 10_000, 30_000, 35_000 ], :bob ],
    [ :maximum, 24_000, [ 10_000, 24_000, 25_000 ], :alice ],
    [ :maximum, 40_000, [ 10_000, 30_000, 31_000 ], :bob ],
    [ :maximum, 30_000, [ 10_000, 30_000, 30_000 ], :alice ],
    [ :maximum, 30_500, [ 10_000, 30_000, 30_500 ], :bob ]
  ].each do |kind, amount, history, winner|
    it "resolves #{kind} challenger #{amount} with monotonic visible history" do
      maximum(alice, 30_000)
      if kind == :manual
        incoming = auction.place_bid!(bidder: bob, amount: amount)
        expect(incoming).to have_attributes(bidder_id: bob.id, amount: amount, origin: "manual")
      else
        maximum(bob, amount)
      end
      assert_state(history, public_send(winner))
    end
  end

  it "uses final partial increments for both incumbent and challenger" do
    auction.update_columns(minimum_increment: 2_000)
    maximum(alice, 23_000)
    auction.place_bid!(bidder: bob, amount: 22_000)
    assert_state([ 10_000, 22_000, 23_000 ], alice)
    maximum(bob, 23_500)
    assert_state([ 10_000, 22_000, 23_000, 23_500 ], bob)
  end

  it "challenges a manual leader at the next minimum, not at the ceiling" do
    auction.place_bid!(bidder: bob, amount: 30_000)
    maximum(alice, 50_000)
    assert_state([ 30_000, 31_000 ], alice)
  end

  it "resets tie priority on an increase to an already established ceiling" do
    maximum(alice, 20_000)
    b = maximum(bob, 30_000)
    a = maximum(alice, 30_000)
    expect(a.priority_sequence).to be > b.priority_sequence
    assert_state([ 10_000, 20_000, 21_000, 30_000, 30_000 ], bob)
    auction.close!(at: auction.ends_at)
    expect(auction.reload.winner_id).to eq(bob.id)
  end

  it "keeps exhausted instructions and reactivates a later competitive increase" do
    maximum(alice, 30_000)
    auction.place_bid!(bidder: bob, amount: 50_000)
    expect { maximum(alice, 40_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("maximum_bid_too_low") }
    assert_state([ 10_000, 30_000, 50_000 ], bob)
    maximum(alice, 60_000)
    assert_state([ 10_000, 30_000, 50_000, 51_000 ], alice)
  end

  it "settles multiple previous bidders without rebidding exhausted maxima" do
    carol = User.create!(name: "Carol")
    maximum(alice, 30_000)
    maximum(bob, 24_000)
    maximum(carol, 40_000)
    maximum(bob, 50_000)
    assert_state([ 10_000, 24_000, 25_000, 30_000, 31_000, 40_000, 41_000 ], bob)
  end

  %w[draft scheduled closed cancelled].each do |state|
    it "rejects maximum on #{state} auction" do
      inactive = create_auction(state: state)
      expect { inactive.set_maximum!(bidder: alice, maximum_amount: 30_000) }.to raise_error(DomainError)
      expect(inactive.maximum_bids).to be_empty
      expect(inactive.bids).to be_empty
    end
  end

  [ nil, 0, -1, 100.5, 100.0, "30000", false, MinorUnitsValidator::MAXIMUM + 1 ].each do |amount|
    it "rejects invalid private amount #{amount.inspect}" do
      expect { maximum(alice, amount) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(auction.maximum_bids).to be_empty
      expect(auction.bids).to be_empty
    end
  end

  it "rejects insufficient first protection and rechecks time even for same amount" do
    expect { maximum(alice, 9_999) }.to raise_error(DomainError) { |e| expect(e.code).to eq("maximum_bid_too_low") }
    maximum(alice, 30_000)
    travel_to(auction.ends_at)
    expect { maximum(alice, 30_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("auction_not_open") }
    expect(auction.ends_at).to eq(Time.current)
  end

  it "preserves invariants across a reproducible mixed-operation stream" do
    users = [ alice, bob, User.create!(name: "Carol") ]
    random = Random.new(3_2026)
    80.times do
      user = users.sample(random: random)
      before = auction.reload.current_price
      begin
        if random.rand(2).zero?
          maximum(user, random.rand(10..90) * 1_000)
        else
          auction.place_bid!(bidder: user, amount: random.rand(10..90) * 1_000)
        end
      rescue DomainError
        expect(auction.reload.current_price).to eq(before)
      end
      amounts = auction.bids.order(:sequence).pluck(:amount)
      expect(amounts).to eq(amounts.sort)
      expect(auction.reload.current_price).to be >= before
      assert_state(amounts, User.find(auction.current_leader_id)) unless amounts.empty?
    end
  end

  it "does not establish dormant tie priority at a manual leader's existing price" do
    maximum(alice, 30_000)
    maximum(bob, 40_000)
    auction.place_bid!(bidder: alice, amount: 50_000)
    expect { maximum(bob, 50_000) }.to raise_error(DomainError) { |e| expect(e.code).to eq("maximum_bid_too_low") }
    expect(auction.maximum_bids.find_by!(bidder: bob)).to have_attributes(maximum_amount: 40_000, priority_sequence: 2)
    maximum(alice, 50_000)
    assert_state([ 10_000, 30_000, 31_000, 40_000, 50_000 ], alice)
  end
end
