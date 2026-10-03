module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :session_id

    def connect
      row = UserSession.resolve(cookies.encrypted[UserSession::COOKIE_NAME])
      reject_unauthorized_connection unless row
      self.current_user = row.user
      self.session_id = row.id
    end
  end
end
