# A separate bounded Redis comparison; the existing PostgreSQL sweep stays read-only.
class AuctionProjectionReconciliationJob
  include Sidekiq::Job
  sidekiq_options queue: "maintenance", retry: 5

  BATCH_SIZE = 100

  def perform(after_id = 0, up_to_id = nil)
    cursor = Integer(after_id)
    raise ArgumentError, "invalid projection cursor" if cursor.negative?
    ceiling = up_to_id.nil? ? Auction.maximum(:id) : Integer(up_to_id)
    return if ceiling.nil?
    raise ArgumentError, "invalid projection ceiling" if ceiling.negative?

    counts = Hash.new(0)
    rows = Auction.where("id > ? AND id <= ?", cursor, ceiling).order(:id).limit(BATCH_SIZE).to_a
    reconciler = AuctionProjectionReconciler.new
    begin
      rows.each do |auction|
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
    self.class.perform_async(rows.last.id, ceiling) if rows.length == BATCH_SIZE
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.error(JSON.generate(event: "auction_projection_reconciliation", result: "postgresql_unavailable",
      error_class: error.class.name))
    raise
  end
end
