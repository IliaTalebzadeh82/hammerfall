# Phase 13 — Observability ExecPlan

Status: active; session 1 checkpoint. Phase 12.5 remains complete at `41bff7c`.

Current milestone: session 1 foundation and focused/live verification complete.
Checkpoint and resume in a fresh conversation.

Completed: `docs/observability.md` defines names, resources, propagation,
dimensions, privacy, histograms, logs, sampling and fail-open behavior. The
optional Compose profile starts Collector, Prometheus, Tempo and provisioned
Grafana data sources. Rails has a bounded OTLP SDK setup, safe HTTP middleware,
bid request/outcome/duration metrics, auction lock wait/extension/close lag,
domain/DB/outbox spans and correlated JSON bid-boundary logs. Focused tests and
live HTTP trace/metric checks pass. No completed Phase 0–12.5 behavior was
intentionally changed.

Verified: see Evidence Index. A real bid trace contains six expected spans;
Prometheus counters and histograms have bounded labels after removing
resource-to-label conversion. W3C inbound parent context was observed in Tempo.
The selected bid/idempotency suite also passes with the Collector endpoint
unreachable. This is a focused failure check, not the full outage campaign.

Remaining: Sidekiq/Kafka context needs careful outbox carrier design and
transport-level tests; instrument both publishers, consumers, projection,
reconciliation, Cable and runtime. Export backlog/lag/repair metrics and create
question-driven dashboards. Verify representative async traces and actual
series. Run mandatory Collector/Prometheus/Tempo/Grafana outage campaign,
privacy/cardinality review, full backend/frontend/security gates, Compose,
browser and hosted CI, then reconcile architecture/runbooks/progress and final
adversarial review. Do not begin Phase 14.

Known limits: API remains unauthenticated demo software. Publishers retain their
transaction-held external I/O. Async propagation/metrics and dashboards are
unimplemented. Ruby OTel metrics SDK is still alpha. Collector v0.136.0 logs
a misleading optional-namespace error on startup; both targets and exported
series work. Existing `api_bundle` volume caused a transient network-dependent
`bundle install` during local image recreation, then recovered. No full
regression or production capacity claim yet.

Relevant files: `docs/observability.md`, `docker-compose.yml`, `.env.example`,
`apps/api/config/`, `apps/api/app/models/auction.rb`, bid controllers, outbox
publishers and consumers. See `docs/context-map.md` for targeted routes.

Relevant ADRs: existing ADR-003/005/010/011/012/013 retain their correctness
contracts. A new ADR is needed only if instrumentation requires a substantial
architecture change.

Next-session starting point: read this plan, handoff and phase spec; inspect
`OutboxEvent`, Sidekiq/Kafka publishers/consumers and their focused specs before
adding public-only W3C context persistence/transport metadata. Preserve stable
event identity and transaction-held delivery. Then add bounded async and
reconciliation metrics, provision dashboards and perform the live campaign.

## Decisions

- `docs/observability.md` is the telemetry contract. Keep metrics dimensions
  bounded, preserve public event identity apart from trace identity, and make
  telemetry loss explicit.
- Prefer explicit selected Ruby instrumentation over auto-enabling all libraries,
  because HTTP bodies, SQL binds and Kafka payloads are private-data risks.
- Collector and storage services are optional Compose peers; application startup
  and auction operation must not depend on their health.
- Explicit Ruby OTLP exporter endpoints require `/v1/traces` and
  `/v1/metrics`. A Ruby metrics view without aggregation dropped counters;
  only histograms now use views. The Prometheus exporter no longer converts
  every resource attribute into a label, which had exposed process PID and
  runtime description on each application series.
- The SDK trace queue is capped at 1,024 spans, exporter calls at one second,
  metric cardinality at 200 series per instrument/reader, and Collector trace
  delivery queue at 100 batches. Telemetry can be dropped on prolonged outage.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Starting tree | `git status --short; git rev-parse HEAD` | clean; `41bff7c9d8ca4cc8ccec9f012541fe772c9bace0` | kickoff inspection |
| Focused Rails, Collector unreachable | `OTEL_ENABLED=true OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:9 bundle exec rspec spec/lib/observability_spec.rb spec/requests/bids_spec.rb spec/requests/maximum_bids_spec.rb spec/requests/idempotency_spec.rb spec/models/auction_closer_spec.rb` | 54 examples, 0 failures; seed 30521 | `/tmp/hammerfall-phase13-focused-checkpoint.log` |
| Focused after privacy/route review | Same command without closer spec | 43 examples, 0 failures; seed 21673 | `/tmp/hammerfall-phase13-focused-after-review.log` |
| Ruby hygiene | targeted `bundle exec rubocop`; `bundle exec rails zeitwerk:check` | 10 files, no offenses; eager load passed | command output |
| Compose syntax | `docker compose config --quiet` and `--profile observability config --quiet` | both passed | command output |
| Live application | `ruby scripts/smoke-proxy-bidding` against OTel-enabled Compose API | passed; four scenarios including concurrent maxima | `/tmp/hammerfall-phase13-proxy-smoke-checkpoint.log` |
| Stack/provisioning | Compose profile startup; Grafana `/api/health`, `/api/datasources`; Prometheus `/api/v1/targets` | services running; Grafana 200 with Prometheus and Tempo sources; both Collector scrape targets up | local Compose inspection |
| HTTP trace | Tempo `/api/traces/30c41a4ac4899164b0a209ec36a4a238` | HTTP maximum command + lock, decision, proxy, DB save, outbox persist; six spans, sensitive-token scan false | Tempo API inspection |
| Inbound propagation | `traceparent: 00-1111…-2222…-01` on GET, query Tempo trace ID | HTTP span appeared under supplied parent span ID | Tempo API inspection |
| Actual metrics/cardinality | Collector `:9464/metrics`, Prometheus series API | bid request/accepted counters and duration/lock histograms with intended seconds buckets; after label fix, application series showed instance (host:PID), bounded job and operation, and OTel scope metadata | local scrape inspection |
