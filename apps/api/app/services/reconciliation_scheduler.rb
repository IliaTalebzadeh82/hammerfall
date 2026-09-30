# Non-authoritative periodic trigger; PostgreSQL leases bound scheduled overlap.
class ReconciliationScheduler
  def initialize(interval: ENV.fetch("RECONCILIATION_INTERVAL", "60"), logger: Rails.logger)
    @interval = Float(interval)
    raise ArgumentError, "interval must be finite and >= 5 seconds" unless @interval.finite? && @interval >= 5
    @logger = logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run_once
    enqueue_scan(ReconciliationLease::POSTGRESQL_STATE, ReconciliationSweepJob)
    enqueue_scan(ReconciliationLease::PROJECTION, AuctionProjectionReconciliationJob)
  end

  def run(once: false)
    @logger.info("reconciliation_scheduler starting interval=#{@interval} once=#{once}")
    loop do
      break if @stopping
      begin
        run_once
      rescue StandardError => error
        @logger.warn("reconciliation_scheduler enqueue_failed error=#{error.class}")
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
    @logger.info("reconciliation_scheduler stopped")
  end

  private

  def enqueue_scan(name, job)
    token = ReconciliationLease.claim(name)
    unless token
      @logger.info(JSON.generate(event: "reconciliation_scheduler", scan: name, result: "already_active"))
      return
    end

    begin
      job.perform_async(0, nil, token)
    rescue StandardError
      ReconciliationLease.release(name, token)
      raise
    end
    @logger.info(JSON.generate(event: "reconciliation_scheduler", scan: name, result: "enqueued"))
  end
end
