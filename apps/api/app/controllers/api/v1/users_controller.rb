module Api
  module V1
    # Deliberately unauthenticated demo identity; never proof of bidder ownership.
    class UsersController < BaseController
      def index
        render_collection(User.all) { |user| { id: user.id, name: user.name } }
      end

      def create
        user = User.create!(resource_params(:user, %w[name]))
        render json: { data: { id: user.id, name: user.name } }, status: :created
      end
    end
  end
end
