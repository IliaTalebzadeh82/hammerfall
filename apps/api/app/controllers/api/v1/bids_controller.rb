module Api
  module V1
    class BidsController < BaseController
      def index
        render_collection(find_auction.bids) { |bid| BidPresenter.new(bid).as_json }
      end

      def create
        auction = find_auction
        attributes = resource_params(:bid, %w[bidder_id amount])
        bidder = User.find(positive_integer(attributes.fetch(:bidder_id) { raise ActionController::ParameterMissing, :bidder_id }))
        bid = auction.place_bid!(bidder: bidder, amount: attributes[:amount])
        render json: { data: BidPresenter.new(bid).as_json }, status: :created
      end
    end
  end
end
