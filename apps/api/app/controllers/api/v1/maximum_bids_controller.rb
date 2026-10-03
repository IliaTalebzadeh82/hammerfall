module Api
  module V1
    class MaximumBidsController < BaseController
      before_action :require_actor!
      rate_limit to: 20, within: 10.seconds, by: -> { current_actor.id },
        store: RateLimitStore.for(:bid), name: "actor-maximum", only: :update,
        with: -> { rate_limit_rejected("bid", retry_after: 10) }
      rate_limit to: 60, within: 10.seconds, by: -> { request.remote_ip },
        store: RateLimitStore.for(:bid), name: "ip-maximum", only: :update,
        with: -> { rate_limit_rejected("bid", retry_after: 10) }
      around_action only: :update do |_controller, action|
        observe_bid_command("set_maximum_bid", &action)
      end

      def update
        key = Idempotency::Executor.validate_key!(request.headers["Idempotency-Key"])
        attributes = resource_params(:maximum_bid, %w[maximum_amount])
        render_idempotent(IdempotentBidding.call(key: key, actor_id: current_actor.id,
          auction_id: positive_integer(params[:id]), operation: "set_maximum_bid", amount: attributes[:maximum_amount]))
      end
    end
  end
end
