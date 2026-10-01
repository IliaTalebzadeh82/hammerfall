require "json"
require "stackprof"
require "time"

module Observability
  module CpuProfile
    DIRECTORY = "/tmp/hammerfall-puma-control"
    TRIGGER = "#{DIRECTORY}/profile.start"

    def self.watch
      Thread.new do
        Thread.current.name = "performance-cpu-profile"
        loop do
          unless File.file?(TRIGGER)
            sleep 0.1
            next
          end

          label, seconds_text = File.read(TRIGGER).split(" ", 2)
          File.delete(TRIGGER)
          next unless label&.match?(/\Ap14-\d{8}T\d{6}Z-[0-9a-f]{8}\z/)

          seconds = Float(seconds_text)
          next unless (1..120).cover?(seconds)

          before = { gc: GC.stat, gc_total_time: GC.total_time,
            rss_kib: rss_kib, at_utc: Time.now.utc.iso8601(6) }
          StackProf.start(mode: :cpu, interval: 1000, raw: true)
          sleep seconds
          StackProf.stop
          after = { gc: GC.stat, gc_total_time: GC.total_time,
            rss_kib: rss_kib, at_utc: Time.now.utc.iso8601(6) }
          File.binwrite("/app/tmp/#{label}.stackprof.dump", Marshal.dump(StackProf.results))
          File.write("/app/tmp/#{label}.gc.json", JSON.pretty_generate(before: before, after: after))
        rescue StandardError => error
          warn "CPU profile failed error_class=#{error.class}"
          StackProf.stop if StackProf.running?
        end
      end
    end

    def self.rss_kib
      File.read("/proc/self/status")[/^VmRSS:\s+(\d+)/, 1].to_i
    end
  end
end
