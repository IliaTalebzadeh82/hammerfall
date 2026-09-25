# Discovery is a hint. Auction#close! owns the lock, clock and finalization.
class AuctionCloser
  class SweepIncomplete < StandardError; end

  TRANSIENT_ERRORS = [ ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::ConnectionFailed, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
    ActiveRecord::QueryCanceled, ActiveRecord::SerializationFailure ].freeze

  def initialize(interval: ENV.fetch("AUCTION_CLOSER_INTERVAL", "1"), batch_size: ENV.fetch("AUCTION_CLOSER_BATCH_SIZE", "100"), logger: Rails.logger)
    @interval = Float(interval)
    @batch_size = Integer(batch_size)
    raise ArgumentError, "interval must be finite and positive" unless @interval.finite? && @interval.positive?
    raise ArgumentError, "batch size must be between 1 and 10000" unless (1..10_000).cover?(@batch_size)
    @logger = logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def candidate_ids
    # A sampled DB wall-clock cutoff permits an index range scan (unlike a
    # volatile clock_timestamp() predicate evaluated separately for each row).
    Auction.where(status: "active").where("ends_at <= ?", AuctionClock.now)
      .order(:ends_at, :id).limit(@batch_size).pluck(:id)
  end

  def run_once
    failures = 0
    candidate_ids.each do |id|
      break if @stopping
      begin
        Auction.find(id).close!
      rescue ActiveRecord::RecordNotFound
        # A privileged deletion between discovery and lookup needs no retry.
      rescue DomainError => error
        # A cancellation won the same lock after discovery.
        unless error.code == "invalid_state_transition"
          @logger.error("auction_closer failure auction_id=#{id} error=#{error.class}")
          raise
        end
      rescue *TRANSIENT_ERRORS => error
        failures += 1
        @logger.warn("auction_closer retry auction_id=#{id} error=#{error.class}")
      rescue StandardError => error
        @logger.error("auction_closer failure auction_id=#{id} error=#{error.class}")
        raise
      end
    end
    failures
  end

  def run(once: false)
    @logger.info("auction_closer starting interval=#{@interval} batch_size=#{@batch_size} once=#{once}")
    loop do
      break if @stopping
      begin
        failures = ApplicationRecord.connection_pool.with_connection { run_once }
        raise SweepIncomplete, "One-shot sweep had transient auction failures; retry the sweep" if once && failures.positive?
      rescue *TRANSIENT_ERRORS => error
        @logger.warn("auction_closer discovery retry error=#{error.class}")
        raise if once
      end
      break if once || @stopping
      # Release database checkout between polls; observe shutdown within 100ms.
      remaining = @interval
      while remaining.positive? && !@stopping
        pause = [ remaining, 0.1 ].min
        sleep(pause)
        remaining -= pause
      end
    end
  ensure
    @logger.info("auction_closer stopped")
  end
end
