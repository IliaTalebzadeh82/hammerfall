module Bidding
  # Called only by Auction commands, after locking and validating fresh state.
  # Completed contests leave all nonleaders exhausted or losing equal-ceiling ties.
  class ProxyResolver
    def initialize(auction)
      @auction = auction
      @sequence = auction.bids.maximum(:sequence) || 0
    end

    def manual(bidder, amount)
      resolve(bidder, amount, manual: true)
    end

    def maximum(instruction)
      if @auction.current_leader_id == instruction.bidder_id
        floor = reserve_floor(instruction.maximum_amount)
        emit(instruction.bidder_id, floor, "automatic") if floor > @auction.current_price
        return
      end

      resolve(instruction.bidder, instruction.maximum_amount, priority: instruction.priority_sequence)
    end

    private

    def resolve(bidder, ceiling, manual: false, priority: nil)
      incumbent_id = @auction.current_leader_id
      if incumbent_id.nil? || incumbent_id == bidder.id
        bid = emit(bidder.id, manual ? ceiling : [ @auction.starting_price, reserve_floor(ceiling) ].max, manual ? "manual" : "automatic")
        finish(bidder.id)
        return bid
      end

      incumbent = @auction.maximum_bids.find_by(bidder_id: incumbent_id)
      incumbent_ceiling = [ @auction.current_price, incumbent&.maximum_amount || 0 ].max
      incoming_wins = ceiling > incumbent_ceiling ||
        (ceiling == incumbent_ceiling && priority && incumbent && priority < incumbent.priority_sequence)

      if incoming_wins
        # Exhaust the incumbent before recording a larger incoming amount.
        emit(incumbent_id, incumbent_ceiling, "automatic") if incumbent_ceiling > @auction.current_price
        visible = manual ? ceiling : [ [ ceiling, @auction.bid_increment_policy.next_after(incumbent_ceiling) ].min, reserve_floor(ceiling) ].max
        incoming_bid = emit(bidder.id, visible, manual ? "manual" : "automatic")
        finish(bidder.id)
      else
        incoming_bid = emit(bidder.id, ceiling, manual ? "manual" : "automatic")
        visible = [ [ incumbent_ceiling, @auction.bid_increment_policy.next_after(ceiling) ].min, reserve_floor(incumbent_ceiling) ].max
        emit(incumbent_id, visible, "automatic")
        finish(incumbent_id)
      end
      incoming_bid
    end

    def emit(bidder_id, amount, origin)
      @sequence += 1
      bid = @auction.bids.build(bidder_id: bidder_id, amount: amount, origin: origin, sequence: @sequence)
      bid.save!(context: :placement)
      @auction.current_price = amount
      bid
    end

    def reserve_floor(ceiling)
      return 0 unless @auction.reserve_price

      [ ceiling, @auction.reserve_price ].min
    end

    def finish(leader_id)
      @auction.current_leader_id = leader_id
    end
  end
end
