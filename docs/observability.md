# Observability

Current diagnostics are framework/Sidekiq logs, Rails `/up`, Compose health checks,
Redis `PING`, queue/retry/Dead counts and test/lint output. These do not constitute
the planned observability system.

OpenTelemetry, Collector, Prometheus, Grafana, Tempo, structured JSON logs, traces,
metrics, and dashboards are deferred to Phase 13. No performance or monitoring
coverage is claimed in Phase 0.
