require "json"
require "stringio"

# Runs before Rails parameter parsing. rack.input may already have been buffered
# by Puma, but Rails never receives more than MAX_BYTES for JSON allocation.
class RequestBodyLimit
  MAX_BYTES = 32 * 1024
  RESPONSE = JSON.generate(error: { code: "request_too_large",
    message: "Request body exceeds the allowed size.", details: {} }).freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless env["PATH_INFO"].to_s.start_with?("/api/v1/")

    declared = env["CONTENT_LENGTH"]
    return reject if declared&.match?(/\A\d+\z/) && declared.to_i > MAX_BYTES

    input = env["rack.input"]
    return @app.call(env) unless input
    body = input.read(MAX_BYTES + 1) || ""
    return reject if body.bytesize > MAX_BYTES

    env["rack.input"] = StringIO.new(body)
    env["CONTENT_LENGTH"] = body.bytesize.to_s
    @app.call(env)
  end

  private

  def reject
    SecurityEvents.emit(category: "request_rejected", outcome: "rejected", reason: "oversized_body")
    [ 413, { "Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store",
      "Content-Length" => RESPONSE.bytesize.to_s }, [ RESPONSE ] ]
  end
end
