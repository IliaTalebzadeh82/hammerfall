# One home for best-effort public invalidations; never part of domain acceptance.
class AuctionPublication
  def self.stream(auction_id)
    "auction:#{auction_id}"
  end

  def self.after_commit(auction_id, revision)
    Auction.current_transaction.after_commit { publish(auction_id, revision) }
  end

  def self.publish(auction_id, revision)
    ActionCable.server.broadcast(stream(auction_id), {
      type: "auction.changed.v1", auction_id: auction_id, revision: revision
    })
  rescue StandardError => error
    # COMMIT already succeeded. Do not turn transport failure into command failure.
    # No raw errors/payloads: reconnect/focus/manual REST reads recover current state.
    Rails.logger.warn("auction_publication failed auction_id=#{auction_id} revision=#{revision} error=#{error.class}")
  end
end
