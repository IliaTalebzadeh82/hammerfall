# Non-authoritative periodic sweep trigger; duplicate schedules are harmless.
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
    ReconciliationSweepJob.perform_async
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
end
