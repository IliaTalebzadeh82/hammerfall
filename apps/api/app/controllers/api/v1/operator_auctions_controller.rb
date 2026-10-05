module Api
  module V1
    class OperatorAuctionsController < BaseController
      before_action :require_internal_operator_api!
      before_action :require_actor!
      before_action :require_operator!

      def show
        auction = find_auction
        projection = AuctionPublicProjection.new
        projection_state = begin
          state = projection.read(auction.id)
          state ? { status: "present", public_revision: state.fetch("public_revision") } : { status: "missing" }
        rescue AuctionPublicProjection::InvalidProjection
          { status: "invalid" }
        rescue RedisClient::Error
          { status: "unavailable" }
        ensure
          projection.close
        end

        outbox = OutboxEvent.where(auction_id: auction.id)
        render json: { data: {
          auction_id: auction.id, status: auction.status, public_revision: auction.public_revision,
          outbox: { sidekiq_pending: outbox.pending.count, kafka_pending: outbox.kafka_pending.count },
          kafka: { audit_receipts: ConsumedKafkaEvent.where(consumer_name: "hammerfall.audit.v1", auction_id: auction.id).count },
          projection: projection_state
        } }
      end

      def reconcile
        auction = find_auction
        audit = OperatorActionAudit.create!(actor: current_actor, auction: auction,
          action: "reconcile_projection", result: "started", created_at: AuctionClock.now)
        reconciler = AuctionProjectionReconciler.new
        begin
          result = reconciler.check(auction)
          audit.update!(result: result.to_s)
          outcome = %i[operator_review repair_failed_review].include?(result) ? "degraded" : "succeeded"
          SecurityEvents.emit(category: "privileged_action", outcome: outcome, reason: "projection_repair")
          render json: { data: { auction_id: auction.id, result: result } }
        rescue StandardError
          audit.update!(result: "failed")
          SecurityEvents.emit(category: "privileged_action", outcome: "degraded", reason: "projection_repair")
          raise
        ensure
          reconciler.close
        end
      end

      private

      def require_internal_operator_api!
        return if ENV["OPERATOR_API_ENABLED"] == "true"

        render_error("resource_not_found", "Requested resource was not found.", :not_found)
      end

      def require_operator!
        require_capability!(current_actor&.operator?) if current_actor
      end
    end
  end
end
