# Phase 13 — Observability ExecPlan

Status: active; session 2 hard checkpoint. Phase 12.5 remains complete at
`41bff7c`. Session 1 foundation was committed at `76df52c`.

Current milestone: distributed/asynchronous telemetry, dashboard and live
failure campaign complete. Stop at this checkpoint and resume in a fresh
conversation for final Phase 13 gates. Do not begin Phase 14.

Completed: Session 1 established the [telemetry contract](../observability.md),
bounded OTLP SDK, HTTP/domain tracing and optional Collector/Prometheus/Tempo/
Grafana stack. Session 2 added bounded W3C metadata to the outbox, Sidekiq
client/server propagation, Kafka transport headers and both consumer spans.
The Kafka v1 payload and job arguments remain unchanged. Publishers, consumers,
Redis projection, reconciliation, Sidekiq and Cable emit bounded metrics and
structured boundary logs. One provisioned Grafana operations dashboard covers
auction/command health, messaging, consistency and runtime. Development Rails
logs now use info level to avoid debug SQL inlining private values. No
PostgreSQL authority, lock order or offset acknowledgment protocol changed.

Verified: see Evidence Index. A 19-span live maximum-command trace crosses
HTTP, outbox, Sidekiq worker/Cable, Kafka producer, audit effect/commit and
projection effect/commit. Focused async tests passed with Collector unreachable;
the live Collector/Prometheus/Tempo/Grafana outages, Kafka and Redis failures,
actual metrics/labels, privacy scan and four sabotage checks were exercised.

Remaining: full backend and frontend regression, static/security gates, full
Compose startup, browser scenarios, final telemetry inspection, hosted CI,
runbook/progress reconciliation and final adversarial review. Run backend
integration tests with `REDIS_URL=redis://redis:6379/1` while the development
stack uses DB 0. Phase 13 is not complete.

Known limits: The API remains an unauthenticated demo. Publishers still hold a
PostgreSQL row lock/connection across external I/O; Phase 14/15 own any
redesign. Kafka lag is a throttled actual broker high-watermark sample after a
commit, so idle/dead consumers leave stale gauges; inspect broker group offsets
for authoritative lag. Ruby metrics SDK remains alpha. Collector v0.136.0
logs a misleading optional-namespace error despite working export. The
30-second Collector outage was not a capacity or full queue-saturation test.
No broad regression, browser or hosted CI has run for this session.

Relevant files: `apps/api/lib/observability.rb`, `lib/observability/sidekiq_middleware.rb`,
the outbox model/publishers, Kafka consumers, Redis projection/reconciler/job,
`infrastructure/observability/grafana/dashboards/hammerfall-operations.json`,
`docs/observability.md` and targeted architecture/runbooks. See the context map.

Relevant ADRs: ADR-003/005/010/011/012/013 retain their correctness contracts.
Transport trace metadata did not change the versioned business event or
transaction protocol, so no new ADR was needed.

Next-session starting point: read this plan, handoff and Phase 13 spec, then
run one broad backend regression with isolated test Redis DB 1 and the frontend
regression. Follow with static/security gates, full Compose/browser checks,
telemetry final inspection and hosted CI. Repair any failures, finish runbooks,
progress and final adversarial review, then mark Phase 13 complete only on
actual evidence. Do not redo this session's outage campaign without a concrete
regression risk.

## Decisions

- `docs/observability.md` is the telemetry contract. Keep metric dimensions
  bounded, preserve public event identity apart from trace identity, and make
  telemetry loss explicit.
- Prefer explicit selected Ruby instrumentation over auto-enabling all libraries,
  because HTTP bodies, SQL binds and Kafka payloads are private-data risks.
- Collector and storage services are optional Compose peers; application startup
  and auction operation must not depend on their health.
- Explicit Ruby OTLP exporter endpoints require `/v1/traces` and
  `/v1/metrics`. A Ruby metrics view without aggregation dropped counters;
  only histograms use views. Resource-to-label conversion remains disabled.
- The SDK trace queue is capped at 1,024 spans, exporter calls at one second,
  metric cardinality at 200 series per instrument/reader, and Collector trace
  delivery queue at 100 batches. Telemetry can be dropped on prolonged outage.
- The outbox stores only bounded `traceparent`/`tracestate`; Kafka headers and
  Sidekiq metadata carry them. Event identity and payload contracts do not
  depend on tracing. Malformed metadata does not poison business work.
- Count gauges omit OTel unit `1`, which otherwise exported `_ratio` suffixes.
  Publisher backlog gauges are global database observations; the dashboard uses
  `max`, not `sum`, across publisher processes.
- Reconciliation log values are per-batch deltas now named `_batch`; exported
  counters are cumulative. Projection telemetry follows the atomic Redis
  decision, and offset commits still follow effects.
- Development debug SQL inlined private maximum/priority values. Info-level
  logging removes those lines; whole command payload keys are filtered from
  Rails request logs. Test
  Redis DB 1 prevents collisions with live development projection keys on DB 0.

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

| Session 2 starting tree | `git status --short; git rev-parse --short HEAD` | clean; `76df52c` | kickoff inspection |
| Async focused, Collector unreachable | `docker compose exec -T -e RAILS_ENV=test -e REDIS_URL=redis://redis:6379/1 -e OTEL_ENABLED=true -e OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:9 api bundle exec rspec` with six focused files | 69 examples, 0 failures, 1 opt-in live Kafka pending; seed 4336 | `/tmp/hammerfall-phase13-async-final-focused.log` |
| Ruby/Compose hygiene | Targeted RuboCop, Zeitwerk, `docker compose --profile observability config --quiet` | 17 files no offenses; eager load/config pass | `/tmp/hammerfall-phase13-async-final-rubocop.log` |
| Real async trace | Tempo `/api/traces/fdd148b5b935809a80a373004be90eaf` after live proxy smoke | 19 spans; HTTP maximum command, Sidekiq enqueue/perform/Cable, Kafka publish/audit/projection/commit share trace | Tempo API inspection; `/tmp/hammerfall-phase13-post-outage-smoke.log` |
| Transport contract | Focused specs plus live `rdkafka` 0.30 headers and Sidekiq job inspection | Kafka payload v1 and job args unchanged; malformed trace header committed valid event | `kafka_outbox_spec.rb`, `observability_spec.rb` |
| Exported async/consistency series | Collector `:9464/metrics`, Prometheus series API, isolated operator-review fixture | Pending/age, duration, lag, worker, projection drift/repair/review, Cable series seen; `operator_review_total{kind="conflict"}=1` | `/tmp/hammerfall-phase13-operator-review.rb`; local scrape inspection |
| Dashboard | Grafana `/api/dashboards/uid/hammerfall-operations`; all PromQL through Prometheus API | 32 panels, 30 valid queries, four question-driven sections | version-controlled JSON and API result |
| Collector outage | Stop Collector, four proxy smokes spaced over ~30 seconds, query database, restore | all four passed; Sidekiq/Kafka pending 0; exporter errors observed; final recovery smoke and trace passed | `/tmp/hammerfall-phase13-prolonged-collector-{1..4}.log`, `/tmp/hammerfall-phase13-post-outage-smoke.log` |
| Prometheus/Tempo/Grafana outages | Stop each independently, run proxy smoke and backlog query, restore | all three smokes passed; both pending counts 0; Collector retried Tempo trace export | `/tmp/hammerfall-phase13-outage-{prometheus,tempo,grafana}.log`, Collector logs |
| Kafka and Redis failures | Stop dependency, run proxy smoke, inspect pending/retries, restore | Kafka pending 16 then 0; one failure/retry metric exported. Redis Sidekiq pending/retrying 16 while Kafka pending 0; drained after recovery; projection consumer required restart | `/tmp/hammerfall-phase13-{kafka,redis}-failure-smoke.log`, publisher logs/metrics |
| Privacy | Tempo maximum trace plus post-fix Compose logs | 17-span maximum trace had no banned private keys; SQL debug lines removed; whole command bodies filtered; no body marker or private values in new logs | Tempo `a87df225f6af328385c808e6e09c281b`; `/tmp/hammerfall-phase13-body-filter-smoke.log`, log scans |
| Cardinality | Prometheus `/api/v1/series` | 1,153 local custom series / 40 metric names at sample time including histogram buckets and historical pre-restart series; no forbidden ID labels; route/group/partition/queue values bounded | local series API inspection; not a production scale claim |
| Sabotage | Temporarily remove Kafka headers; propagate span-completion failure; unbound reason; add maximum span attr | each corresponding test failed (1 example, 1 failure), exact source restored by byte comparison; focused suite then green | `/tmp/hammerfall-phase13-sabotage-{kafka,failopen,cardinality,privacy}.log` |
| Test isolation correction | Initial combined test run against Redis DB 0, rerun on DB 1 | 5 Redis projection failures from live/test key collision; isolated rerun 38 examples, 0 failures, 1 pending | `/tmp/hammerfall-phase13-async-contract{,-isolated}.log` |
| Final narrow checks | Isolated reconciliation/lease specs; privacy/Cable specs; targeted RuboCop; 30 PromQL queries | 19 + 17 examples, 0 failures; changed Ruby lint clean; dashboard queries valid | `/tmp/hammerfall-phase13-final-{reconciliation,privacy-spec,privacy-rubocop}.log` |
