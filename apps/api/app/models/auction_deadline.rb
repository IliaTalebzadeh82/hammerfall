# Pure arithmetic, separate from acquiring authoritative decision time.
class AuctionDeadline
  def self.due?(ends_at, decision_time)
    decision_time >= ends_at
  end

  def self.extended_end(ends_at, decision_time, policy: ClosingPolicy.new("regular"))
    remaining = ends_at - decision_time
    remaining.positive? && remaining <= policy.window ? ends_at + policy.extension : ends_at
  end
end
