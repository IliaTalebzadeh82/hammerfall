module Api
  module V1
    class MaximumBidsController < BaseController
      def update
        key = Idempotency::Executor.validate_key!(request.headers["Idempotency-Key"])
        attributes = resource_params(:maximum_bid, %w[bidder_id maximum_amount])
        actor_id = positive_integer(attributes.fetch(:bidder_id) { raise ActionController::ParameterMissing, :bidder_id })
        render_idempotent(IdempotentBidding.call(key: key, actor_id: actor_id,
          auction_id: positive_integer(params[:id]), operation: "set_maximum_bid", amount: attributes[:maximum_amount]))
      end
    end
  end
end
