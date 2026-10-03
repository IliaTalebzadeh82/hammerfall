class AuctionChannel < ActionCable::Channel::Base
  def subscribed
    count = RateLimitStore.for(:cable).increment("cable:subscribe:#{session_id}", 1, expires_in: 1.minute)
    if count > 40
      SecurityEvents.emit(category: "rate_limit", outcome: "rejected", reason: "quota")
      reject_subscription
      return
    end
    row = UserSession.where("expires_at > clock_timestamp()").find_by(id: session_id, user_id: current_user.id)
    unless row
      reject_subscription
      return
    end
    value = params[:auction_id]
    text = value.to_s if value.is_a?(String) || value.is_a?(Integer)
    unless text && text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 9_223_372_036_854_775_807
      reject_subscription
      return
    end
    id = text.to_i
    unless Auction.exists?(id)
      reject_subscription
      return
    end
    stream_from AuctionPublication.stream(id)
    SecurityEvents.emit(category: "cable", outcome: "succeeded", reason: "subscription")
  rescue RateLimitStore::BackendUnavailable
    reject_subscription
  end

  private

  def reject_subscription
    SecurityEvents.emit(category: "cable", outcome: "rejected", reason: "subscription")
    reject
  end
end
