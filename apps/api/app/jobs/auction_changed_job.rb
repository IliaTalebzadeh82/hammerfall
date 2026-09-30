# A repeatable, public-only hint. Never resolves a bid or mutates auction state.
class AuctionChangedJob
  include Sidekiq::Job
  sidekiq_options queue: "notifications", retry: 5

  def perform(auction_id, requested_revision)
    id = Integer(auction_id)
    revision = Integer(requested_revision)
    raise ArgumentError, "invalid auction notification" unless id.positive? && revision.positive?

    current = Auction.where(id: id).pick(:public_revision)
    return unless current # Privileged deletion; nothing public remains to refresh.
    raise "public revision regressed" if current < revision

    # Current state may be ahead of the queued hint. Duplicate/reordered jobs
    # therefore only request a fresh REST read at a non-regressing revision.
    AuctionPublication.broadcast(id, current)
  end
end
