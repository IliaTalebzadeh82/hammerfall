class IdempotencyRecord < ApplicationRecord
  OPERATIONS = %w[place_bid set_maximum_bid].freeze
  belongs_to :actor, class_name: "User"

  def readonly?
    (persisted? && status_in_database == "completed") || super
  end

  def self.prune_expired!(batch_size: ENV.fetch("IDEMPOTENCY_PRUNE_BATCH_SIZE", "1000"))
    limit = Integer(batch_size)
    raise ArgumentError, "prune batch must be between 1 and 10000" unless (1..10_000).cover?(limit)
    # Transaction-start DB time is conservative and suitable for retention, not
    # for auction eligibility. Skip locked rows and delete only one bounded batch.
    transaction do
      ids = where(status: "completed").where("expires_at <= CURRENT_TIMESTAMP")
        .order(:expires_at, :id).limit(limit).lock("FOR UPDATE SKIP LOCKED").pluck(:id)
      where(id: ids).delete_all
    end
  end
end
