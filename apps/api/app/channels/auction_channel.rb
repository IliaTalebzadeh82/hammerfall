class AuctionChannel < ActionCable::Channel::Base
  def subscribed
    value = params[:auction_id]
    text = value.to_s if value.is_a?(String) || value.is_a?(Integer)
    unless text && text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 9_223_372_036_854_775_807
      reject
      return
    end
    id = text.to_i
    unless Auction.exists?(id)
      reject
      return
    end
    stream_from AuctionPublication.stream(id)
  end
end
