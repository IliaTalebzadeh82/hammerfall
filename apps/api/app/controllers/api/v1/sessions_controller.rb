module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :verify_authenticated_csrf, only: :create
      before_action :no_store
      before_action :require_actor!, only: %i[show destroy]
      rate_limit to: 10, within: 1.minute, by: -> { request.remote_ip },
        store: RateLimitStore.for(:auth), name: "ip", only: :create,
        with: -> { rate_limit_rejected("auth", retry_after: 60) }
      rate_limit to: 5, within: 1.minute, by: :login_limit_key,
        store: RateLimitStore.for(:auth), name: "login", only: :create,
        with: -> { rate_limit_rejected("auth", retry_after: 60) }

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
          SecurityEvents.emit(category: "authentication", outcome: "rejected", reason: "invalid_credentials")
          return render_error("invalid_credentials", "Invalid credentials.", :unauthorized)
        end
        actor = User.find_by("lower(login) = ?", login.downcase)
        digest = actor&.password_digest || DUMMY_DIGEST
        unless BCrypt::Password.new(digest).is_password?(password) && actor&.password_digest
          SecurityEvents.emit(category: "authentication", outcome: "rejected", reason: "invalid_credentials")
          return render_error("invalid_credentials", "Invalid credentials.", :unauthorized)
        end
        current_user_session&.destroy!
        token = UserSession.issue!(actor)
        cookies.encrypted[UserSession::COOKIE_NAME] = { value: token, httponly: true, secure: Rails.env.production?,
          same_site: :lax, path: "/", expires: UserSession::LIFETIME.from_now }
        SecurityEvents.emit(category: "authentication", outcome: "succeeded", reason: "login")
        render json: { data: { id: actor.id, name: actor.name, role: actor.role }, csrf_token: UserSession.csrf_token(token) }, status: :created
      end

      def destroy
        current_user_session.destroy!
        cookies.delete(UserSession::COOKIE_NAME, path: "/")
        SecurityEvents.emit(category: "authentication", outcome: "succeeded", reason: "logout")
        head :no_content
      end

      private

      def login_limit_key
        supplied = params[:session]
        login = supplied.is_a?(ActionController::Parameters) ? supplied[:login] : nil
        Digest::SHA256.hexdigest(login.is_a?(String) ? login.downcase.byteslice(0, 254) : "invalid")
      end

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
