# Development-only HTTP client for the real cookie and CSRF contract.
require "json"
require "net/http"
require "uri"

class AuthenticatedSmoke
  DEMO_PASSWORD = "hammerfall-local-demo-only"

  attr_reader :actor_id

  def initialize(base:, login:, password: ENV.fetch("SMOKE_DEMO_PASSWORD", DEMO_PASSWORD))
    @base = base
    response = transport(:post, "/api/v1/session", base: base,
      headers: { "X-Hammerfall-Login" => "1" }, body: { session: { login: login, password: password } })
    if response.code.to_i == 429
      sleep(Integer(response["Retry-After"]))
      response = transport(:post, "/api/v1/session", base: base,
        headers: { "X-Hammerfall-Login" => "1" }, body: { session: { login: login, password: password } })
    end
    raise "Demo login failed (HTTP #{response.code})" unless response.code.to_i == 201

    @cookie = response.get_fields("Set-Cookie")&.first&.split(";", 2)&.first
    raise "Login did not set a cookie" unless @cookie

    payload = JSON.parse(response.body)
    @csrf = payload.fetch("csrf_token")
    @actor_id = payload.fetch("data").fetch("id")
  end

  def request(method, path, body: nil, key: nil, base: @base)
    headers = { "Cookie" => @cookie, "X-CSRF-Token" => @csrf }
    headers["Idempotency-Key"] = key if key
    response = transport(method, path, base: base, headers: headers, body: body)
    raw = response.body.to_s
    { status: response.code.to_i, body: raw.empty? ? nil : JSON.parse(raw),
      raw: raw, replayed: response["Idempotency-Replayed"] == "true",
      retry_after: response["Retry-After"], instance: response["X-Hammerfall-Instance"] }
  end

  def expect(method, path, status:, body: nil, key: nil, base: @base)
    result = request(method, path, body: body, key: key, base: base)
    if result[:status] == 429 && status != 429
      sleep(Integer(result.fetch(:retry_after)))
      result = request(method, path, body: body, key: key, base: base)
    end
    raise "#{method.to_s.upcase} #{path}: expected #{status}, got #{result[:status]}: #{result[:raw]}" unless result[:status] == status

    result[:body]
  end

  def logout
    expect(:delete, "/api/v1/session", status: 204)
  end

  private

  def transport(method, path, base:, headers:, body: nil)
    uri = URI.join(base, path)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put,
      patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
    message = klass.new(uri)
    headers.each { |name, value| message[name] = value }
    if body
      message["Content-Type"] = "application/json"
      message.body = JSON.generate(body)
    end
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 20) do |http|
      http.request(message)
    end
  end
end
