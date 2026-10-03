module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :session_id

    def connect
      count = RateLimitStore.for(:cable).increment("cable:connect:#{request.remote_ip}", 1, expires_in: 1.minute)
      if count > 20
        SecurityEvents.emit(category: "rate_limit", outcome: "rejected", reason: "quota")
        reject_unauthorized_connection
      end
      row = UserSession.resolve(cookies.encrypted[UserSession::COOKIE_NAME])
      unless row
        SecurityEvents.emit(category: "cable", outcome: "rejected", reason: "connection")
        reject_unauthorized_connection
      end
      self.current_user = row.user
      self.session_id = row.id
      SecurityEvents.emit(category: "cable", outcome: "succeeded", reason: "connection")
    rescue RateLimitStore::BackendUnavailable
      SecurityEvents.emit(category: "cable", outcome: "rejected", reason: "connection")
      reject_unauthorized_connection
    end
  end
end
