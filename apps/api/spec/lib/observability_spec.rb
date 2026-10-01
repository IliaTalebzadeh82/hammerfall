require "rails_helper"
require "stringio"

RSpec.describe Observability do
  it "filters whole auction and bidding request payloads from Rails logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    params = { "auction" => { "title" => "private marker", "description" => "private body" },
      "maximum_bid" => { "maximum_amount" => 999_999 }, "id" => "123" }
    filtered = filter.filter(params)
    expect(filtered).to include("auction" => "[FILTERED]", "maximum_bid" => "[FILTERED]", "id" => "123")
    expect(filtered.to_s).not_to include("private marker", "private body", "999999")
  end

  describe ".route" do
    it "uses bounded route templates without preserving IDs or query strings" do
      expect(described_class.route("/api/v1/auctions/123/bids")).to eq("/api/v1/auctions/:id/bids")
      expect(described_class.route("/api/v1/auctions/123/maximum-bid")).to eq("/api/v1/auctions/:id/maximum-bid")
      expect(described_class.route("/api/v1/private/secret")).to eq("other")
      expect(described_class.route("\xFF".b)).to eq("other")
    end
  end

  describe "passive telemetry" do
    it "extracts only bounded W3C trace fields and ignores malformed metadata" do
      allow(described_class).to receive(:enabled?).and_return(true)
      propagator = OpenTelemetry::Trace::Propagation::TraceContext::TextMapPropagator.new
      allow(OpenTelemetry).to receive(:propagation).and_return(propagator)
      trace_id = SecureRandom.hex(16)
      parent = "00-#{trace_id}-#{SecureRandom.hex(8)}-01"
      carrier = { "traceparent" => parent, "baggage" => "private=secret" }

      described_class.with_carrier(carrier) do
        expect(OpenTelemetry::Trace.current_span.context.hex_trace_id).to eq(trace_id)
        expect(described_class.carrier.keys).to eq([ "traceparent" ])
      end
      expect(described_class.extracted_context("traceparent" => "x" * 100)).to be_nil
      expect(described_class.extracted_context("traceparent" => [ parent ])).to be_nil
      expect(described_class.extracted_context("traceparent" => parent, "tracestate" => "x" * 513)).to be_nil
    end

    it "passes trace metadata through Sidekiq without changing the public job arguments" do
      carrier = { "traceparent" => "00-#{SecureRandom.hex(16)}-#{SecureRandom.hex(8)}-01" }
      allow(described_class).to receive(:carrier).and_return(carrier)
      allow(described_class).to receive(:trace).and_yield
      job = { "args" => [ 17, 2 ] }
      client_calls = 0
      Observability::SidekiqMiddleware::Client.new.call(AuctionChangedJob, job, "notifications", nil) { client_calls += 1 }
      expect(client_calls).to eq(1)
      expect(job).to eq("args" => [ 17, 2 ], "otel_trace" => carrier)
      expect(job.to_json).not_to include("maximum_amount", "priority_sequence", "idempotency_key")
      expect(described_class).to receive(:with_carrier).with(carrier).and_yield
      server_calls = 0
      Observability::SidekiqMiddleware::Server.new.call(AuctionChangedJob.new, job, "notifications") { server_calls += 1 }
      expect(server_calls).to eq(1)
    end

    it "enqueues once if trace metadata cannot be attached" do
      allow(described_class).to receive(:carrier).and_return(
        "traceparent" => "00-#{SecureRandom.hex(16)}-#{SecureRandom.hex(8)}-01")
      allow(described_class).to receive(:trace).and_yield
      calls = 0
      Observability::SidekiqMiddleware::Client.new.call(AuctionChangedJob, {}.freeze, "notifications", nil) do
        calls += 1
      end
      expect(calls).to eq(1)
    end

    it "drops an oversized tracestate before durable storage" do
      allow(described_class).to receive(:enabled?).and_return(true)
      parent = "00-#{SecureRandom.hex(16)}-#{SecureRandom.hex(8)}-01"
      propagator = double("propagator")
      allow(propagator).to receive(:inject) do |carrier|
        carrier["traceparent"] = parent
        carrier["tracestate"] = "x" * 513
      end
      allow(OpenTelemetry).to receive(:propagation).and_return(propagator)
      expect(described_class.carrier).to eq("traceparent" => parent)
    end

    it "runs business work once when span startup fails" do
      allow(described_class).to receive(:enabled?).and_return(true)
      tracer = instance_double(OpenTelemetry::Trace::Tracer)
      allow(OpenTelemetry.tracer_provider).to receive(:tracer).and_return(tracer)
      allow(tracer).to receive(:in_span).and_raise(StandardError, "collector down")
      calls = 0

      result = described_class.trace("hammerfall.bid.decide") { calls += 1; :accepted }

      expect(result).to eq(:accepted)
      expect(calls).to eq(1)
    end

    it "returns business work once when span completion fails" do
      allow(described_class).to receive(:enabled?).and_return(true)
      tracer = instance_double(OpenTelemetry::Trace::Tracer)
      allow(OpenTelemetry.tracer_provider).to receive(:tracer).and_return(tracer)
      allow(tracer).to receive(:in_span) do |*_args, **_kwargs, &block|
        block.call
        raise StandardError, "export failed"
      end
      calls = 0

      expect(described_class.trace("hammerfall.bid.decide") { calls += 1; :accepted }).to eq(:accepted)
      expect(calls).to eq(1)
    end

    it "preserves business exceptions and does not rerun the command" do
      allow(described_class).to receive(:enabled?).and_return(true)
      tracer = instance_double(OpenTelemetry::Trace::Tracer)
      allow(OpenTelemetry.tracer_provider).to receive(:tracer).and_return(tracer)
      allow(tracer).to receive(:in_span) { |*_args, **_kwargs, &block| block.call }
      calls = 0

      expect do
        described_class.trace("hammerfall.bid.decide") { calls += 1; raise DomainError.new("bid_too_low", "rejected") }
      end.to raise_error(DomainError, "rejected")
      expect(calls).to eq(1)
    end

    it "keeps private and arbitrary values out of span attributes" do
      allow(described_class).to receive(:enabled?).and_return(true)
      tracer = instance_double(OpenTelemetry::Trace::Tracer)
      allow(OpenTelemetry.tracer_provider).to receive(:tracer).and_return(tracer)
      expect(tracer).to receive(:in_span).with("hammerfall.bid.decide",
        attributes: { "hammerfall.operation" => "place_bid", "hammerfall.event_type" => "other" },
        kind: :internal, record_exception: false).and_yield

      described_class.trace("hammerfall.bid.decide", attributes: {
        "hammerfall.operation" => "place_bid",
        "hammerfall.event_type" => "untrusted",
        "maximum_amount" => 999_999,
        "idempotency_key" => "private-key"
      }) { :accepted }
    end

    it "normalizes metric labels and discards unapproved dimensions" do
      allow(described_class).to receive(:enabled?).and_return(true)
      instrument = instance_double(OpenTelemetry::Metrics::Instrument::Counter)
      previous_instruments = described_class.instance_variable_get(:@instruments)
      described_class.instance_variable_set(:@instruments, { "hammerfall_bid_rejected" => instrument })
      expect(instrument).to receive(:add).with(1,
        attributes: { "operation" => "place_bid", "reason" => "other" })

      described_class.counter("hammerfall_bid_rejected", attributes: {
        operation: "place_bid", reason: "secret-key-or-message", auction_id: 123,
        maximum_amount: 999_999
      })
    ensure
      described_class.instance_variable_set(:@instruments, previous_instruments)
    end

    it "bounds async result, group, partition, and drift labels" do
      allow(described_class).to receive(:enabled?).and_return(true)
      counter = instance_double(OpenTelemetry::Metrics::Instrument::Counter)
      gauge = instance_double(OpenTelemetry::Metrics::Instrument::Gauge)
      previous_instruments = described_class.instance_variable_get(:@instruments)
      described_class.instance_variable_set(:@instruments, {
        "hammerfall_kafka_consumed" => counter,
        "hammerfall_kafka_consumer_lag" => gauge,
        "hammerfall_projection_drift" => counter
      })
      expect(counter).to receive(:add).with(1,
        attributes: { "consumer_group" => "other", "result" => "other" })
      expect(counter).to receive(:add).with(1, attributes: { "kind" => "other" })
      expect(gauge).to receive(:record).with(9,
        attributes: { "consumer_group" => KafkaAuditConsumer::GROUP, "partition" => "other" })
      described_class.counter("hammerfall_kafka_consumed", attributes: {
        consumer_group: "secret-group", result: "private-result", auction_id: 123
      })
      described_class.counter("hammerfall_projection_drift", attributes: { kind: "auction-123" })
      described_class.gauge("hammerfall_kafka_consumer_lag", 9,
        attributes: { consumer_group: KafkaAuditConsumer::GROUP, partition: 9000 })
    ensure
      described_class.instance_variable_set(:@instruments, previous_instruments)
    end

    it "writes correlated JSON while excluding private fields" do
      allow(described_class).to receive(:enabled?).and_return(true)
      span_context = double(valid?: true, hex_trace_id: "a" * 32, hex_span_id: "b" * 16)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(double(context: span_context))
      previous_stdout = $stdout
      $stdout = StringIO.new

      described_class.log(level: :info, operation: "place_bid", component: "http",
        result: "accepted", maximum_amount: 999_999, idempotency_key: "private-key")

      payload = JSON.parse($stdout.string)
      expect(payload).to include("operation" => "place_bid", "trace_id" => "a" * 32,
        "span_id" => "b" * 16)
      expect(payload.keys).not_to include("maximum_amount", "idempotency_key")
    ensure
      $stdout = previous_stdout
    end
  end
end
