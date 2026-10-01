module Observability
  module DbPoolDiagnostics
    # Rails 8.1's ConnectionPool#checkout covers acquisition and verification.
    # Queue#poll with a timeout is the actual blocking wait for a free connection.
    # Both are sampled only in an explicitly enabled profiling run.
    module Checkout
      def checkout(...)
        return super unless Observability.performance_diagnostics?

        Observability.sample_db_pool(self)
        started = Observability.monotonic
        super
      ensure
        if started
          Observability.histogram("hammerfall_db_checkout_duration", Observability.monotonic - started)
        end
      end
    end

    module Queue
      def poll(timeout = nil)
        return super unless timeout && Observability.performance_diagnostics?

        started = Observability.monotonic
        super
      ensure
        if started
          Observability.histogram("hammerfall_db_pool_wait_duration", Observability.monotonic - started)
        end
      end
    end
  end
end
