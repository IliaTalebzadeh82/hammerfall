require "rails_helper"
require "tmpdir"

RSpec.describe ChaosCrash do
  let(:event_id) { SecureRandom.uuid }

  def configure(boundary:, target: event_id, confirm: "phase-16-local-crash")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_CONFIRM").and_return(confirm)
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_CRASH_BOUNDARY").and_return(boundary)
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_EVENT_ID").and_return(target)
  end

  it "is inert without explicit opt-in or for a different event" do
    expect(Process).not_to receive(:kill)
    expect(Process).not_to receive(:exit!)
    described_class.at!("kafka_delivered", event_id)
    described_class.at_command!("command_committed", 42)
    configure(boundary: "kafka_delivered", target: SecureRandom.uuid)
    described_class.at!("kafka_delivered", event_id)
  end

  it "kills only at the configured local boundary and event" do
    configure(boundary: "kafka_delivered")
    Dir.mktmpdir do |dir|
      stub_const("ChaosCrash::MARKER_DIR", dir)
      expect(Process).to receive(:kill).with("KILL", Process.pid).once
      described_class.at!("audit_effect_committed", event_id)
      described_class.at!("kafka_delivered", event_id)
      described_class.at!("kafka_delivered", event_id)
      expect(Dir.children(dir)).to have_attributes(length: 1)
    end
  end

  it "is inert in production even with opt-in variables" do
    configure(boundary: "kafka_delivered")
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    expect(Process).not_to receive(:kill)
    described_class.at!("kafka_delivered", event_id)
  end

  it "scopes command death to a named auction and never activates in production" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_CONFIRM").and_return("phase-16-local-crash")
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_CRASH_BOUNDARY").and_return("command_committed")
    allow(ENV).to receive(:[]).with("HAMMERFALL_CHAOS_AUCTION_ID").and_return("42")
    Dir.mktmpdir do |dir|
      stub_const("ChaosCrash::MARKER_DIR", dir)
      expect(Process).to receive(:exit!).with(137).once
      described_class.at_command!("command_before_commit", 42)
      described_class.at_command!("command_committed", 43)
      described_class.at_command!("command_committed", 42)
      described_class.at_command!("command_committed", 42)
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      described_class.at_command!("command_committed", 42)
    end
  end
end
