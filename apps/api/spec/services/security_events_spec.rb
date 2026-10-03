require "rails_helper"

RSpec.describe SecurityEvents do
  it "emits only approved bounded security fields" do
    allow(Observability).to receive(:counter)
    allow(Observability).to receive(:log)

    described_class.emit(category: "authentication", outcome: "rejected", reason: "invalid_credentials")
    expect(Observability).to have_received(:counter).with("hammerfall_security_events",
      attributes: { category: "authentication", outcome: "rejected", security_reason: "invalid_credentials" })
    expect(Observability).to have_received(:log).with(level: :warn, component: "security.authentication",
      result: "rejected", security_reason: "invalid_credentials")
    expect { described_class.emit(category: "authentication", outcome: "rejected", reason: "raw-login-or-secret") }
      .to raise_error(ArgumentError, "Invalid security event")
  end
end
