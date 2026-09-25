# Pure arithmetic, separate from acquiring authoritative decision time.
class AuctionDeadline
  WINDOW = 60
  EXTENSION = 90

  def self.due?(ends_at, decision_time)
    decision_time >= ends_at
  end

  def self.extended_end(ends_at, decision_time)
    remaining = ends_at - decision_time
    remaining.positive? && remaining <= WINDOW ? ends_at + EXTENSION : ends_at
  end
end
