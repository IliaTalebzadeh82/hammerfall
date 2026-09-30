# A separate bounded Redis comparison; the existing PostgreSQL sweep stays read-only.
class AuctionProjectionReconciliationJob
  include Sidekiq::Job
  sidekiq_options queue: "maintenance", retry: 5

  BATCH_SIZE = 100

  def perform(after_id = 0, up_to_id = nil, lease_token = nil)
    cursor = Integer(after_id)
    raise ArgumentError, "invalid projection cursor" if cursor.negative?
    return unless lease_active?(lease_token, cursor)

    ceiling = up_to_id.nil? ? Auction.maximum(:id) : Integer(up_to_id)
    if ceiling.nil?
      release_lease(lease_token, cursor)
      return
    end
    raise ArgumentError, "invalid projection ceiling" if ceiling.negative?

    counts = Hash.new(0)
    rows = Auction.where("id > ? AND id <= ?", cursor, ceiling).order(:id).limit(BATCH_SIZE).to_a
    reconciler = AuctionProjectionReconciler.new
    begin
      rows.each_with_index do |auction, index|
        return unless lease_active?(lease_token, cursor) if index.positive? && (index % ReconciliationLease::HEARTBEAT_ROWS).zero?

        counts[:checked] += 1
        begin
          result = reconciler.check(auction)
        rescue AuctionProjectionReconciler::RepairUnavailable
          counts[:drift] += 1
          counts[:repair_attempt] += 1
          counts[:repair_failure] += 1
          counts[:unavailable] += 1
          raise
        rescue AuctionProjectionReconciler::ProjectionUnavailable
          counts[:unavailable] += 1
          raise
        end
        counts[:healthy] += 1 if result == :healthy
        counts[:drift] += 1 unless result == :healthy
        counts[:repair_attempt] += 1 if %i[repaired raced repair_failed_review].include?(result)
        counts[:repair] += 1 if result == :repaired
        counts[:repair_failure] += 1 if result == :repair_failed_review
        counts[:operator_review] += 1 if %i[operator_review repair_failed_review].include?(result)
      end
    ensure
      reconciler.close
      Rails.logger.info(JSON.generate(event: "auction_projection_reconciliation_metrics",
        after_id: cursor, up_to_id: ceiling, checked: counts[:checked], healthy: counts[:healthy],
        auction_projection_drift_total: counts[:drift],
        auction_projection_repair_attempt_total: counts[:repair_attempt],
        auction_projection_repair_total: counts[:repair],
        auction_projection_repair_failure_total: counts[:repair_failure],
        unavailable: counts[:unavailable],
        operator_review: counts[:operator_review]))
    end
    if rows.length == BATCH_SIZE
      if lease_token
        return unless ReconciliationLease.advance(ReconciliationLease::PROJECTION, lease_token, cursor, rows.last.id)
      end

      args = [ rows.last.id, ceiling ]
      args << lease_token if lease_token
      self.class.perform_async(*args)
    else
      release_lease(lease_token, cursor)
    end
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.error(JSON.generate(event: "auction_projection_reconciliation", result: "postgresql_unavailable",
      error_class: error.class.name))
    raise
  end

  private

  def lease_active?(token, cursor)
    return true unless token
    return true if ReconciliationLease.renew(ReconciliationLease::PROJECTION, token, cursor)

    Rails.logger.warn(JSON.generate(event: "auction_projection_reconciliation", result: "lease_lost"))
    false
  end

  def release_lease(token, cursor)
    ReconciliationLease.release(ReconciliationLease::PROJECTION, token, cursor) if token
  end
end
