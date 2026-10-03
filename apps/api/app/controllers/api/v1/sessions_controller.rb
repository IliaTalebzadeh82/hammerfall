module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :verify_authenticated_csrf, only: :create
      before_action :no_store
      before_action :require_actor!, only: %i[show destroy]

      DUMMY_DIGEST = BCrypt::Password.create("no-such-user", cost: BCrypt::Engine::DEFAULT_COST).to_s

      def show
        render json: { data: identity, csrf_token: UserSession.csrf_token(session_token) }
      end

      def create
        unless request.media_type == "application/json" && request.headers["X-Hammerfall-Login"] == "1"
          return render_error("invalid_request", "JSON login request required.", :bad_request)
        end
        values = resource_params(:session, %w[login password])
        login = values[:login]
        password = values[:password]
        unless login.is_a?(String) && password.is_a?(String) && login.length <= 254 && password.bytesize <= 72
          return render_error("invalid_credentials", "Invalid credentials.", :unauthorized)
        end
        actor = User.find_by("lower(login) = ?", login.downcase)
        digest = actor&.password_digest || DUMMY_DIGEST
        unless BCrypt::Password.new(digest).is_password?(password) && actor
          return render_error("invalid_credentials", "Invalid credentials.", :unauthorized)
        end
        current_user_session&.destroy!
        token = UserSession.issue!(actor)
        cookies.encrypted[UserSession::COOKIE_NAME] = { value: token, httponly: true, secure: Rails.env.production?,
          same_site: :lax, path: "/", expires: UserSession::LIFETIME.from_now }
        render json: { data: { id: actor.id, name: actor.name, role: actor.role }, csrf_token: UserSession.csrf_token(token) }, status: :created
      end

      def destroy
        current_user_session.destroy!
        cookies.delete(UserSession::COOKIE_NAME, path: "/")
        head :no_content
      end

      private

      def no_store
        response.set_header("Cache-Control", "no-store")
        response.set_header("Vary", "Cookie")
      end

      def identity
        { id: current_actor.id, name: current_actor.name, role: current_actor.role }
      end
    end
  end
end
