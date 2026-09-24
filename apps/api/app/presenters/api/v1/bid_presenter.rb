module Api
  module V1
    class BidPresenter
      def initialize(bid)
        @bid = bid
      end

      def as_json
        {
          id: @bid.id,
          auction_id: @bid.auction_id,
          bidder_id: @bid.bidder_id,
          amount: @bid.amount,
          sequence: @bid.sequence,
          currency: Auction::CURRENCY,
          created_at: @bid.created_at.iso8601(6)
        }
      end
    end
  end
end
