module Api
  module V1
    class BidsController < BaseController
      before_action :require_actor!, only: :create
      rate_limit to: 20, within: 10.seconds, by: -> { current_actor.id },
        store: RateLimitStore.for(:bid), name: "actor-place-bid", only: :create,
        with: -> { rate_limit_rejected("bid", retry_after: 10) }
      rate_limit to: 60, within: 10.seconds, by: -> { request.remote_ip },
        store: RateLimitStore.for(:bid), name: "ip-place-bid", only: :create,
        with: -> { rate_limit_rejected("bid", retry_after: 10) }
      around_action only: :create do |_controller, action|
        observe_bid_command("place_bid", &action)
      end

      def index
        raise ActionController::BadRequest if params.key?(:after_id)
        render_collection(find_auction.bids, order_key: :sequence) { |bid| BidPresenter.new(bid).as_json }
      end

      def create
        key = Idempotency::Executor.validate_key!(request.headers["Idempotency-Key"])
        attributes = resource_params(:bid, %w[amount])
        render_idempotent(IdempotentBidding.call(key: key, actor_id: current_actor.id,
          auction_id: positive_integer(params[:auction_id]), operation: "place_bid", amount: attributes[:amount]))
      end
    end
  end
end
