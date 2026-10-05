module Api
  module V1
    class AuctionPresenter
      def initialize(auction)
        @auction = auction
      end

      def as_json
        {
          id: @auction.id,
          public_revision: @auction.public_revision,
          title: @auction.title,
          description: @auction.description,
          status: @auction.status,
          currency: Auction::CURRENCY,
          starting_price: @auction.starting_price,
          current_price: @auction.current_price,
          reserve_status: @auction.reserve_status,
          closing_policy: @auction.closing_policy,
          minimum_increment: @auction.bid_increment_policy.increment_at(@auction.current_price),
          starts_at: @auction.starts_at.iso8601(6),
          ends_at: @auction.ends_at.iso8601(6),
          original_ends_at: @auction.original_ends_at.iso8601(6),
          closed_at: @auction.closed_at&.iso8601(6),
          current_leader_id: @auction.current_leader_id,
          winner_id: @auction.winner_id,
          created_at: @auction.created_at.iso8601(6),
          updated_at: @auction.updated_at.iso8601(6)
        }
      end
    end
  end
end
