module ApplicationCable
  # Public invalidations only. Supplied bidder IDs are not credentials.
  class Connection < ActionCable::Connection::Base
  end
end
