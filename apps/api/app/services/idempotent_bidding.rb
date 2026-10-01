# The two protected HTTP commands share idempotency without changing the domain
# entry points used by tests, seeds or the autonomous closer.
class IdempotentBidding
  def self.call(key:, actor_id:, auction_id:, operation:, amount:)
    Idempotency::Executor.validate_key!(key)
    actor = User.find(actor_id)
    field = operation == "place_bid" ? "amount" : "maximum_amount"
    extended = false
    outcome = Idempotency::Executor.call(key: key, actor_id: actor.id, operation: operation,
      auction_id: auction_id, arguments: { field => amount }) do
      auction = Auction.find(auction_id)
      case operation
      when "place_bid"
        bid = auction.place_bid!(bidder: actor, amount: amount)
        extended = auction.saved_change_to_ends_at?
        [ 201, { data: Api::V1::BidPresenter.new(bid).as_json } ]
      when "set_maximum_bid"
        auction.set_maximum!(bidder: actor, maximum_amount: amount)
        extended = auction.saved_change_to_ends_at?
        [ 200, { data: { auction_id: auction.id, bidder_id: actor.id, accepted: true } } ]
      end
    end
    Observability.counter("hammerfall_auction_extensions") if extended && !outcome.replayed && outcome.status < 400
    outcome
  end
end
