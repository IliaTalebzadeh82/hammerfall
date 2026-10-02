# Explicit, event-scoped process death for Phase 16 local crash-window evidence.
# Never active in production; an injected process dies at most once.
class ChaosCrash
  BOUNDARIES = %w[kafka_delivered audit_effect_committed].freeze
  COMMAND_BOUNDARIES = %w[command_before_commit command_committed].freeze
  COMMAND_MARKER_DIR = "/tmp"

  def self.at!(boundary, event_id)
    return unless Rails.env.development? || Rails.env.test?
    return unless BOUNDARIES.include?(boundary)
    return unless ENV["HAMMERFALL_CHAOS_CONFIRM"] == "phase-16-local-crash"
    return unless ENV["HAMMERFALL_CHAOS_CRASH_BOUNDARY"] == boundary
    return unless ENV["HAMMERFALL_CHAOS_EVENT_ID"] == event_id

    STDERR.puts("chaos_crash boundary=#{boundary} event_id=#{event_id}")
    STDERR.flush
    Process.kill("KILL", Process.pid)
  end

  def self.at_command!(boundary, auction_id)
    return unless Rails.env.development? || Rails.env.test?
    return unless COMMAND_BOUNDARIES.include?(boundary)
    return unless ENV["HAMMERFALL_CHAOS_CONFIRM"] == "phase-16-local-crash"
    return unless ENV["HAMMERFALL_CHAOS_CRASH_BOUNDARY"] == boundary
    return unless ENV["HAMMERFALL_CHAOS_AUCTION_ID"] == auction_id.to_s

    marker = File.join(COMMAND_MARKER_DIR, "hammerfall-chaos-#{boundary}-#{Integer(auction_id)}")
    begin
      File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0600) { }
    rescue Errno::EEXIST
      return
    end

    STDERR.puts("chaos_crash boundary=#{boundary} auction_id=#{auction_id}")
    STDERR.flush
    Process.exit!(137)
  end
end
