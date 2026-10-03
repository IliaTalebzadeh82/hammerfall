module Api
  module V1
    # Display names only for users with public bids; no account directory.
    class UsersController < BaseController
      def index
        render_collection(User.where(id: Bid.select(:bidder_id))) { |user| { id: user.id, name: user.name } }
      end
    end
  end
end
