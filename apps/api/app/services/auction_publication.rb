# Public Cable invalidations; outbox publisher owns durable enqueue intent.
class AuctionPublication
  def self.stream(auction_id)
    "auction:#{auction_id}"
  end

  def self.broadcast(auction_id, revision)
    ActionCable.server.broadcast(stream(auction_id), {
      type: "auction.changed.v1", auction_id: auction_id, revision: revision
    })
  end
end
