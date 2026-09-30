# Independent PostgreSQL outbox poller. It never decides an auction outcome.
class OutboxPublisher
  class EnqueueFailed < StandardError; end

  def initialize(interval: ENV.fetch("OUTBOX_PUBLISH_INTERVAL", "1"), batch_size: ENV.fetch("OUTBOX_PUBLISH_BATCH_SIZE", "100"), logger: Rails.logger)
    @interval = Float(interval)
    @batch_size = Integer(batch_size)
    raise ArgumentError, "interval must be finite and positive" unless @interval.finite? && @interval.positive?
    raise ArgumentError, "batch size must be between 1 and 1000" unless (1..1000).cover?(@batch_size)
    @logger = logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run_once
    published = 0
    failed = 0
    @batch_size.times do
      break if @stopping
      found = false
      OutboxEvent.transaction do
        event = OutboxEvent.due.order(:next_attempt_at, :id).lock("FOR UPDATE SKIP LOCKED").first
        if event
          found = true
          begin
            jid = AuctionChangedJob.perform_async(event.auction_id, event.public_revision)
            raise EnqueueFailed, "Sidekiq returned no job ID" if jid.nil?
          rescue StandardError => error
            # Persist a retry; a failed/unknown enqueue may already have reached Redis.
            attempts = event.attempts + 1
            delay = [ 2**[ attempts, 8 ].min, 300 ].min
            event.update!(attempts: attempts, last_error: error.class.name.to_s.first(255), next_attempt_at: Time.current + delay)
            @logger.warn("outbox_publisher enqueue_failed event_id=#{event.event_id} error=#{error.class}")
            failed += 1
          else
            # An acknowledgment failure rolls this transaction back. A later
            # poll may enqueue the same event again, as intended.
            event.update!(published_at: Time.current, attempts: event.attempts + 1, last_error: nil)
            published += 1
          end
        end
      end
      break unless found
    end
    metrics = backlog_metrics
    @logger.info("outbox_publisher published=#{published} failed=#{failed} backlog=#{metrics[:backlog]} due=#{metrics[:due]} retries=#{metrics[:retries]} oldest_age_seconds=#{metrics[:oldest_age_seconds]}")
    { published: published, failed: failed, **metrics }
  end

  def backlog_metrics
    pending = OutboxEvent.pending
    oldest = pending.minimum(:occurred_at)
    { backlog: pending.count, due: OutboxEvent.due.count, retries: pending.where("attempts > 0").count,
      oldest_age_seconds: oldest ? [ (Time.current - oldest).to_i, 0 ].max : 0 }
  end

  def run(once: false)
    @logger.info("outbox_publisher starting interval=#{@interval} batch_size=#{@batch_size} once=#{once}")
    loop do
      break if @stopping
      begin
        result = ApplicationRecord.connection_pool.with_connection { run_once }
        raise EnqueueFailed, "#{result[:failed]} enqueue attempts failed" if once && result[:failed].positive?
      rescue StandardError => error
        @logger.warn("outbox_publisher cycle_failed error=#{error.class}")
        raise if once
      end
      break if once || @stopping
      remaining = @interval
      while remaining.positive? && !@stopping
        pause = [ remaining, 0.1 ].min
        sleep(pause)
        remaining -= pause
      end
    end
  ensure
    @logger.info("outbox_publisher stopped")
  end
end
