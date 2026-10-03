module Api
  module V1
    class AuctionsController < BaseController
      before_action :require_actor!, only: %i[create update schedule activate close cancel]
      def index
        render_collection(Auction.all) { |auction| AuctionPresenter.new(auction).as_json }
      end

      def show
        render_auction(find_auction)
      end

      # Explicit eventual read. The ordinary show endpoint always reads PostgreSQL.
      def public_state
        auction_id = positive_integer(params[:id])
        response.set_header("Cache-Control", "no-store")
        projection = AuctionPublicProjection.new
        begin
          state = projection.read(auction_id)
        rescue RedisClient::Error, AuctionPublicProjection::InvalidProjection => error
          Rails.logger.warn("auction_public_state projection_unavailable auction_id=#{auction_id} error=#{error.class}")
          state = nil
        ensure
          projection.close
        end
        if state
          render json: { data: state.fetch("data").merge("id" => auction_id,
            "public_revision" => state.fetch("public_revision"), "currency" => Auction::CURRENCY),
            meta: { source: "redis", event_occurred_at: state.fetch("occurred_at"),
              projected_at: Time.at(state.fetch("projected_at_ms") / 1000.0).utc.iso8601(3),
              age_seconds: [ (Time.current - Time.iso8601(state.fetch("occurred_at"))).to_i, 0 ].max } }
        else
          auction = Auction.find(auction_id)
          public_data = AuctionPresenter.new(auction).as_json.stringify_keys
          render json: { data: public_data.slice("id", "public_revision", "currency", *KafkaEventCodec::DATA_KEYS),
            meta: { source: "postgresql", observed_at: Time.current.iso8601(3), age_seconds: 0 } }
        end
      end

      def create
        return unless require_capability!(AuctionPolicy.new(current_actor).create?)
        auction = Auction.create_draft!(auction_params.merge(seller: current_actor))
        render_auction(auction, status: :created)
      end

      def update
        auction = find_auction
        return unless require_capability!(AuctionPolicy.new(current_actor, auction).manage?)
        render_auction(auction.edit_draft!(auction_params))
      end

      def schedule
        return unless require_capability!(AuctionPolicy.new(current_actor).transition?)
        render_auction(find_auction.schedule!)
      end

      def activate
        return unless require_capability!(AuctionPolicy.new(current_actor).transition?)
        render_auction(find_auction.activate!)
      end

      def close
        return unless require_capability!(AuctionPolicy.new(current_actor).transition?)
        render_auction(find_auction.close!)
      end

      def cancel
        auction = find_auction
        return unless require_capability!(AuctionPolicy.new(current_actor, auction).manage?)
        render_auction(auction.cancel!)
      end

      private

      def auction_params
        resource_params(:auction, Auction::EDITABLE_FIELDS)
      end

      def render_auction(auction, status: :ok)
        render json: { data: AuctionPresenter.new(auction).as_json }, status: status
      end
    end
  end
end
