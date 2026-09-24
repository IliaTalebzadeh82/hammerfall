module Api
  module V1
    class MaximumBidsController < BaseController
      def update
        auction = find_auction
        attributes = resource_params(:maximum_bid, %w[bidder_id maximum_amount])
        bidder = User.find(positive_integer(attributes.fetch(:bidder_id) { raise ActionController::ParameterMissing, :bidder_id }))
        auction.set_maximum!(bidder: bidder, maximum_amount: attributes[:maximum_amount])
        render json: { data: { auction_id: auction.id, bidder_id: bidder.id, accepted: true } }
      end
    end
  end
end
