# Public Cable invalidations; outbox publisher owns durable enqueue intent.
class AuctionPublication
  def self.stream(auction_id)
    "auction:#{auction_id}"
  end

  def self.broadcast(auction_id, revision)
    result = Observability.trace("hammerfall.websocket.broadcast") do
      ActionCable.server.broadcast(stream(auction_id), {
        type: "auction.changed.v1", auction_id: auction_id, revision: revision
      })
    end
    Observability.counter("hammerfall_websocket_broadcasts", attributes: { result: "succeeded" })
    result
  rescue StandardError
    Observability.counter("hammerfall_websocket_broadcasts", attributes: { result: "failed" })
    raise
  end
end
