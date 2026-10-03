# Development-only representative proof that a login identifier shares one Redis quota.
require "json"
require "net/http"
require "securerandom"

abort "development only" unless Rails.env.development?
bases = [ "http://api:3000", "http://api-replica-b:3000" ]
login = "phase20-no-such-user-#{SecureRandom.hex(6)}"
results = 6.times.map do |index|
  uri = URI.join(bases[index % 2], "/api/v1/session")
  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request["X-Hammerfall-Login"] = "1"
  request.body = JSON.generate(session: { login: login, password: "wrong" })
  response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
  [ response.code.to_i, response["X-Hammerfall-Instance"], JSON.parse(response.body).dig("error", "code"), index.even? ? "a" : "b" ]
end
raise "shared identifier quota failed: #{results.inspect}" unless results.first(5).all? { |status, _, code| status == 401 && code == "invalid_credentials" } &&
  results.last.values_at(0, 2, 3) == [ 429, "rate_limited", "b" ] &&
  results.first(5).map { |row| row[1] }.uniq.sort == %w[a b]
puts JSON.generate(result: "PASS", statuses: results.map(&:first), targets: results.map(&:last))
