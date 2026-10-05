# Bounded taxonomy; no actor, IP, login, token, raw key or private amount.
class SecurityEvents
  CATEGORIES = %w[authentication authorization rate_limit request_rejected privileged_action cable].freeze
  OUTCOMES = %w[succeeded rejected degraded].freeze
  REASONS = %w[login logout invalid_credentials invalid_session forbidden self_bid quota backend_unavailable
    oversized_body lifecycle connection subscription projection_repair].freeze

  def self.emit(category:, outcome:, reason:)
    raise ArgumentError, "Invalid security event" unless CATEGORIES.include?(category) && OUTCOMES.include?(outcome) && REASONS.include?(reason)
    Observability.counter("hammerfall_security_events", attributes: { category: category, outcome: outcome, security_reason: reason })
    Observability.log(level: outcome == "succeeded" ? :info : :warn,
      component: "security.#{category}", result: outcome, security_reason: reason)
  end
end
