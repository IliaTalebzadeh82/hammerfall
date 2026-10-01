require "rails_helper"
require "stringio"

RSpec.describe Observability do
  describe ".route" do
    it "uses bounded route templates without preserving IDs or query strings" do
      expect(described_class.route("/api/v1/auctions/123/bids")).to eq("/api/v1/auctions/:id/bids")
      expect(described_class.route("/api/v1/auctions/123/maximum-bid")).to eq("/api/v1/auctions/:id/maximum-bid")
      expect(described_class.route("/api/v1/private/secret")).to eq("other")
      expect(described_class.route("\xFF".b)).to eq("other")
    end
  end

  describe "passive telemetry" do
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
