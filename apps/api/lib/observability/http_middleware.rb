module Observability
  class HttpMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless Observability.enabled?

      started = Observability.monotonic
      method = env["REQUEST_METHOD"].to_s
      method = "OTHER" unless %w[GET POST PUT PATCH DELETE].include?(method)
      route = Observability.route(env["PATH_INFO"].to_s)
      context = extract_context(env)
      response = Observability.with_context(context) do
        Observability.trace("HTTP #{method} #{route}",
          attributes: { "http.request.method" => method, "http.route" => route },
          kind: :server) { @app.call(env) }
      end
      response
    ensure
      if started
        status_class = response ? "#{response.first.to_i / 100}xx" : "5xx"
        dimensions = { route: route, method: method, status_class: status_class }
        Observability.counter("hammerfall_http_requests", attributes: dimensions)
        Observability.histogram("hammerfall_http_duration", Observability.monotonic - started,
          attributes: dimensions)
      end
    end

    private

    def extract_context(env)
      OpenTelemetry.propagation.extract(env,
        getter: OpenTelemetry::Common::Propagation.rack_env_getter)
    rescue StandardError
      OpenTelemetry::Context.current
    end
  end
end
