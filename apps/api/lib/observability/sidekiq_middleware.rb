module Observability
  module SidekiqMiddleware
    class Client
      def call(_worker_class, job, _queue, _redis_pool)
        Observability.trace("hammerfall.sidekiq.enqueue", kind: :producer) do
          begin
            carrier = Observability.carrier
            job["otel_trace"] = carrier if carrier.key?("traceparent")
          rescue StandardError
            # Telemetry metadata must never prevent an enqueue.
          end
          yield
        end
      end
    end

    class Server
      def call(_worker, job, _queue)
        started = Observability.monotonic
        result = "succeeded"
        Observability.with_carrier(job["otel_trace"]) do
          Observability.trace("hammerfall.sidekiq.perform", kind: :consumer) { yield }
        end
      rescue StandardError
        result = "failed"
        raise
      ensure
        Observability.counter("hammerfall_sidekiq_jobs", attributes: { queue: _queue, result: result })
        Observability.histogram("hammerfall_sidekiq_job_duration", Observability.monotonic - started,
          attributes: { queue: _queue, result: result }) if started
      end
    end
  end
end
