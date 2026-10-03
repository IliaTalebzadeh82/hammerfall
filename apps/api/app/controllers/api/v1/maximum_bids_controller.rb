module Api
  module V1
    class MaximumBidsController < BaseController
      before_action :require_actor!
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
