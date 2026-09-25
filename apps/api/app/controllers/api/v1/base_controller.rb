module Api
  module V1
    class BaseController < ApplicationController
      wrap_parameters false
      # Presentation calibration only; bidding still uses post-lock PostgreSQL time.
      after_action :set_presentation_time

      rescue_from Idempotency::Executor::InvalidKey do |error|
        render_error(error.code, error.message, :bad_request)
      end

      rescue_from DomainError do |error|
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

      def render_idempotent(outcome)
        response.set_header("Idempotency-Replayed", "true") if outcome.replayed
        render json: outcome.body, status: outcome.status
      end

      def set_presentation_time
        response.set_header("X-Server-Time", Time.current.iso8601(3))
      end

      def render_error(code, message, status, details = {})
        set_presentation_time
        render json: { error: { code: code, message: message, details: details } }, status: status
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
