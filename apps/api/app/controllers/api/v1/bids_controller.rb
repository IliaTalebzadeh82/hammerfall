module Api
  module V1
    class BidsController < BaseController
      around_action only: :create do |_controller, action|
        observe_bid_command("place_bid", &action)
      end

      def index
        raise ActionController::BadRequest if params.key?(:after_id)
        render_collection(find_auction.bids, order_key: :sequence) { |bid| BidPresenter.new(bid).as_json }
      end

      def create
        key = Idempotency::Executor.validate_key!(request.headers["Idempotency-Key"])
        attributes = resource_params(:bid, %w[bidder_id amount])
        actor_id = positive_integer(attributes.fetch(:bidder_id) { raise ActionController::ParameterMissing, :bidder_id })
        render_idempotent(IdempotentBidding.call(key: key, actor_id: actor_id,
          auction_id: positive_integer(params[:auction_id]), operation: "place_bid", amount: attributes[:amount]))
      end
    end
  end
end
