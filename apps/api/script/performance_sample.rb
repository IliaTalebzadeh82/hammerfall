#!/usr/bin/env ruby
# Samples the API process from a separate container process during local load.
# Output is aggregate JSON lines only; it contains no request or auction data.
require "json"
require "socket"
require "time"

duration = Float(ARGV.fetch(0))
interval = Float(ARGV.fetch(1, "0.2"))
abort "invalid sampling interval" unless duration.positive? && interval >= 0.1

socket_path = "/tmp/hammerfall-puma-control/puma.sock"
abort "enable PERFORMANCE_DIAGNOSTICS on the API" unless File.socket?(socket_path)

def puma_stats(path)
  socket = UNIXSocket.new(path)
  socket.write("GET /stats?token=none HTTP/1.0\r\n\r\n")
  response = socket.read
  JSON.parse(response.split("\r\n\r\n", 2).fetch(1))
ensure
  socket&.close
end

def process_state
  status = File.readlines("/proc/1/status").filter_map do |line|
    match = line.match(/\A(VmRSS|Threads):\s+(\d+)/)
    [ match[1], match[2].to_i ] if match
  end.to_h
  stat_fields = File.read("/proc/1/stat").split(") ", 2).fetch(1).split
  fds = Dir.children("/proc/1/fd").filter_map do |fd|
    File.readlink("/proc/1/fd/#{fd}")
  rescue Errno::ENOENT
    nil
  end
  socket_inodes = fds.filter_map { |fd| fd[/\Asocket:\[(\d+)\]\z/, 1] }
  tcp_ports = [ "/proc/1/net/tcp", "/proc/1/net/tcp6" ].flat_map do |path|
    File.readlines(path).drop(1).filter_map do |line|
      columns = line.split
      next unless socket_inodes.include?(columns[9])

      [ columns[9], columns[1].split(":").last.to_i(16), columns[2].split(":").last.to_i(16) ]
    end
  end
  {
    "rss_kib" => status["VmRSS"], "threads" => status["Threads"],
    "cpu_ticks" => stat_fields[11].to_i + stat_fields[12].to_i,
    "fds" => fds.length,
    "socket_fds" => fds.count { |fd| fd.start_with?("socket:") },
    "pipe_fds" => fds.count { |fd| fd.start_with?("pipe:") },
    "http_socket_fds" => tcp_ports.count { |_, local, _| local == 3000 },
    "postgres_socket_fds" => tcp_ports.count { |_, _, remote| remote == 5432 },
    "redis_socket_fds" => tcp_ports.count { |_, _, remote| remote == 6379 },
    "kafka_socket_fds" => tcp_ports.count { |_, _, remote| remote == 9092 },
    "otel_socket_fds" => tcp_ports.count { |_, _, remote| remote == 4318 }
  }
end

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration
loop do
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  break if now >= deadline

  puts JSON.generate({ "at_utc" => Time.now.utc.iso8601(6), "monotonic" => now,
    "puma" => puma_stats(socket_path), "process" => process_state })
  $stdout.flush
  sleep interval
end
