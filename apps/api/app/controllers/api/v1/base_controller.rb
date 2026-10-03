module Api
  module V1
    class BaseController < ApplicationController
      wrap_parameters false
      before_action :verify_authenticated_csrf, if: :unsafe_request?
      # Presentation calibration only; bidding still uses post-lock PostgreSQL time.
      after_action :set_presentation_time
      after_action :set_local_instance

      rescue_from Idempotency::Executor::InvalidKey do |error|
        render_error(error.code, error.message, :bad_request)
      end
      rescue_from RateLimitStore::BackendUnavailable do
        response.set_header("Retry-After", "5")
        render_error("limiter_unavailable", "Please try again shortly.", :service_unavailable)
      end

      rescue_from DomainError do |error|
        SecurityEvents.emit(category: "authorization", outcome: "rejected", reason: "self_bid") if error.code == "seller_self_bid"
        render_error(error.code, error.message, :unprocessable_content, error.details)
      end
      rescue_from ActiveRecord::RecordInvalid do |error|
        render_error("validation_failed", "Validation failed.", :unprocessable_content, error.record.errors.to_hash)
      end
      rescue_from ActiveRecord::RecordNotFound do |error|
        code = { "Auction" => "auction_not_found", "User" => "user_not_found" }.fetch(error.model, "resource_not_found")
        render_error(code, "Requested resource was not found.", :not_found)
      end
      rescue_from ActionController::ParameterMissing, ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError do
        render_error("invalid_request", "Request parameters are missing or invalid.", :bad_request)
      end

      private

      def session_token
        @session_token ||= cookies.encrypted[UserSession::COOKIE_NAME]
      end

      def current_user_session
        @current_user_session ||= UserSession.resolve(session_token)
      end

      def current_actor
        current_user_session&.user
      end

      def require_actor!
        return if current_actor
        SecurityEvents.emit(category: "authentication", outcome: "rejected", reason: "invalid_session")
        render_error("authentication_required", "Sign in to continue.", :unauthorized)
      end

      def require_capability!(allowed)
        return true if allowed
        SecurityEvents.emit(category: "authorization", outcome: "rejected", reason: "forbidden")
        render_error("forbidden", "This action is not permitted.", :forbidden)
        false
      end

      def rate_limit_rejected(operation, retry_after:)
        Observability.counter("hammerfall_security_rate_limits", attributes: { operation: operation, result: "rejected" })
        SecurityEvents.emit(category: "rate_limit", outcome: "rejected", reason: "quota")
        response.set_header("Retry-After", retry_after.to_s)
        render_error("rate_limited", "Too many requests. Try again later.", :too_many_requests)
      end

      def unsafe_request?
        !request.get? && !request.head? && !request.options?
      end

      def verify_authenticated_csrf
        return unless session_token && current_user_session
        return if UserSession.valid_csrf?(session_token, request.headers["X-CSRF-Token"])
        render_error("invalid_csrf", "Request verification failed.", :forbidden)
      end

      def render_idempotent(outcome)
        @observability_replayed = outcome.replayed
        @observability_reason = outcome.body.dig("error", "code") if outcome.status >= 400
        SecurityEvents.emit(category: "authorization", outcome: "rejected", reason: "self_bid") if @observability_reason == "seller_self_bid"
        response.set_header("Idempotency-Replayed", "true") if outcome.replayed
        render json: outcome.body, status: outcome.status
      end

      def set_presentation_time
        response.set_header("X-Server-Time", Time.current.iso8601(3))
      end

      def set_local_instance
        instance = ENV["HAMMERFALL_INSTANCE"]
        response.set_header("X-Hammerfall-Instance", instance) if Rails.env.development? && %w[a b].include?(instance)
      end

      def render_error(code, message, status, details = {})
        @observability_reason = code
        set_presentation_time
        render json: { error: { code: code, message: message, details: details } }, status: status
      end

      def observe_bid_command(operation)
        started = Observability.monotonic
        Observability.counter("hammerfall_bid_requests", attributes: { operation: operation })
        failure = nil
        yield
      rescue StandardError => error
        failure = error
        raise
      ensure
        if started
          reason = failure ? observed_failure_reason(failure) : @observability_reason
          result = if failure
            reason ? "rejected" : "error"
          elsif @observability_replayed
            "replayed"
          elsif response.status < 400
            "accepted"
          else
            "rejected"
          end
          if result == "accepted"
            Observability.counter("hammerfall_bid_accepted", attributes: { operation: operation })
          elsif result == "rejected"
            Observability.counter("hammerfall_bid_rejected",
              attributes: { operation: operation, reason: reason || "other" })
          end
          Observability.histogram("hammerfall_bid_processing_duration", Observability.monotonic - started,
            attributes: { operation: operation, result: result })
          Observability.log(level: :info, operation: operation, component: "http", result: result,
            error_class: failure&.class&.name)
        end
      end

      def observed_failure_reason(error)
        case error
        when Idempotency::Executor::InvalidKey, DomainError then error.code
        when ActiveRecord::RecordInvalid then "validation_failed"
        when ActiveRecord::RecordNotFound
          { "Auction" => "auction_not_found", "User" => "user_not_found" }.fetch(error.model, "other")
        when ActionController::ParameterMissing, ActionController::BadRequest,
          ActionDispatch::Http::Parameters::ParseError then "invalid_request"
        end
      end

      def resource_params(root, fields)
        value = params.require(root)
        unless value.is_a?(ActionController::Parameters) && (value.keys - fields.map(&:to_s)).empty?
          raise ActionController::BadRequest
        end
        if value.values.any? { |item| item.is_a?(ActionController::Parameters) || item.is_a?(Array) }
          raise ActionController::BadRequest
        end
        value.permit(*fields)
      end

      def positive_integer(value, maximum: 9_223_372_036_854_775_807)
        text = value.to_s
        raise ActionController::BadRequest unless text.match?(/\A[1-9]\d{0,18}\z/) && text.to_i <= maximum
        text.to_i
      end

      def find_auction
        Auction.find(positive_integer(params[:auction_id] || params[:id]))
      end

      # Bounded, stable history/list pagination; IDs are not commit ordering.
      def render_collection(scope, order_key: :id)
        limit = params.key?(:limit) ? positive_integer(params[:limit], maximum: 100) : 20
        cursor = "after_#{order_key}"
        scope = scope.where(scope.klass.arel_table[order_key].gt(positive_integer(params[cursor]))) if params.key?(cursor)
        rows = scope.order(order_key).limit(limit + 1).to_a
        page = rows.first(limit)
        render json: {
          data: page.map { |record| yield record },
          meta: { "next_#{cursor}" => rows.length > limit ? page.last.public_send(order_key) : nil }
        }
      end
    end
  end
end
