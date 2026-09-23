module Api
  module V1
    class AuctionsController < BaseController
      def index
        render_collection(Auction.all) { |auction| AuctionPresenter.new(auction).as_json }
      end

      def show
        render_auction(find_auction)
      end

      def create
        auction = Auction.create_draft!(auction_params)
        render_auction(auction, status: :created)
      end

      def update
        render_auction(find_auction.edit_draft!(auction_params))
      end

      def schedule
        render_auction(find_auction.schedule!)
      end

      def activate
        render_auction(find_auction.activate!)
      end

      def close
        render_auction(find_auction.close!)
      end

      def cancel
        render_auction(find_auction.cancel!)
      end

      private

      def auction_params
        resource_params(:auction, Auction::EDITABLE_FIELDS)
      end

      def render_auction(auction, status: :ok)
        render json: { data: AuctionPresenter.new(auction).as_json }, status: status
      end
    end
  end
end
