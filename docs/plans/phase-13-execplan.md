# Phase 13 — Observability ExecPlan

Status: complete; final local and hosted gates passed. Phase 12.5 remains complete at
`41bff7c`. Session 1 foundation was committed at `76df52c`.

Current milestone: Phase 13 closure. Distributed/asynchronous telemetry,
dashboard and live failure campaign were completed in session 2; broad local
and hosted verification is complete. Phase 14 has not begun.

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

Remaining: no Phase 13 implementation or verification work. Broad backend and
frontend regressions, static/security gates, gated live Kafka, full Compose
startup, smokes, browser, live telemetry inspection and hosted CI passed.
Backend integration tests use `REDIS_URL=redis://redis:6379/1` while
development uses DB 0.

Known limits: The API remains an unauthenticated demo. Publishers still hold a
PostgreSQL row lock/connection across external I/O; Phase 14/15 own any
redesign. Kafka lag is a throttled actual broker high-watermark sample after a
commit, so idle/dead consumers leave stale gauges; inspect broker group offsets
for authoritative lag. Ruby metrics SDK remains alpha. Collector v0.136.0
logs a misleading optional-namespace error despite working export. The
30-second Collector outage was not a capacity or full queue-saturation test.
The final documentation-only commit receives a separate hosted run; the
implementation run and jobs are indexed below.

Relevant files: `apps/api/lib/observability.rb`, `lib/observability/sidekiq_middleware.rb`,
the outbox model/publishers, Kafka consumers, Redis projection/reconciler/job,
`infrastructure/observability/grafana/dashboards/hammerfall-operations.json`,
`docs/observability.md` and targeted architecture/runbooks. See the context map.

Relevant ADRs: ADR-003/005/010/011/012/013 retain their correctness contracts.
Transport trace metadata did not change the versioned business event or
transaction protocol, so no new ADR was needed.

Next-session starting point: Phase 13 is complete. Start Phase 14 only on an
explicit user request, using this plan for Phase 13 evidence and the compact
handoff for current boundaries. Do not repeat the outage campaign without a
new risk.

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
| Final broad backend | `docker compose exec -T -e RAILS_ENV=test -e REDIS_URL=redis://redis:6379/1 api bundle exec rspec` | 439 examples, 0 failures, 3 expected gated pending; seed 48627 | `/tmp/hammerfall-phase13-final-rspec.log` |
| Final gated live Kafka | Same test container with `KAFKA_BOOTSTRAP_SERVERS=kafka:9092 PHASE12_LIVE_KAFKA=1 PHASE12_5_LIVE_KAFKA=1`, two integration files, `--tag live_kafka` | 3 examples, 0 failures; seed 43549. First container attempt used host-only broker address; interruption left a test event, so the test database was reset before the final clean run. | `/tmp/hammerfall-phase13-final-live-kafka.log`; `/tmp/hammerfall-phase13-final-test-db-reset.log` |
| Final Ruby static/security | Full `bundle exec rubocop`; `bundle exec rails zeitwerk:check`; `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`; `bin/bundler-audit` | 118 files, no offenses; eager load passed; 0 Brakeman errors/warnings; no vulnerable gems | `/tmp/hammerfall-phase13-final-{rubocop,zeitwerk,brakeman,audit}.log` |
| Final frontend gates | `npm test`, `npm run lint`, `npm run format:check`, `npm run typecheck`, `npm run build` | 73 tests across 10 files; lint/format/types/build passed | `/tmp/hammerfall-phase13-final-web-{test,lint,format,types,build}.log` |
| Final Compose build/start | `OTEL_ENABLED=true docker compose --profile observability up -d --build --wait --wait-timeout 360` | API, web, PostgreSQL, Redis, Sidekiq, publishers, Kafka/consumers, closer, scheduler, Collector, Prometheus, Tempo and Grafana healthy; Kafka init exited successfully | `/tmp/hammerfall-phase13-final-compose.log` |
| Normal Compose configuration | `OTEL_ENABLED=false docker compose up -d --wait --wait-timeout 360`; both `docker compose config --quiet` modes | Normal application/transport services healthy after telemetry-enabled inspection; optional peers are not startup dependencies | `/tmp/hammerfall-phase13-final-normal-compose.log` |
| Final full-stack smokes | CI-equivalent health, Redis/Kafka topic, scheduler/publishers, Kafka, sequential API, closer, concurrent, proxy and prune commands against rebuilt Compose | All passed; `ALL_SMOKES_PASSED` | Finalization terminal output; labelled records retained |
| Final real browser | Seed; `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` | 7/7 passed in 1.8 minutes with Google Chrome 154.0.8037.57; real API/Cable/reconnect/closer scenarios | `/tmp/hammerfall-phase13-final-browser.log` |
| Final distributed trace | Tempo `/api/traces/44b497010f2815d076eedea54ddff707` from rebuilt proxy smoke | 19 spans, six services, one root, no missing parents; HTTP maximum command 46.8 ms, later Kafka/Sidekiq spans each bounded; payload v1 remains separate from headers | Tempo API inspection; correlated API/worker logs |
| Final metrics/dashboard | Prometheus `series` and instant `query` APIs, all provisioned dashboard PromQL | Current bid/lag/backlog/repair counters and seconds histograms; no forbidden ID label keys; normalized route templates; 30/30 valid dashboard queries, 28 with data after smokes, two empty failure/drift queries; both Collector scrape targets `up=1` | Prometheus and Grafana APIs; dashboard UID `hammerfall-operations` |
| Final privacy and repair | Tempo manual/maximum/rejected/replay traces; recent Compose service logs; controlled missing Redis key for auction 389, `AuctionProjectionReconciler#check`, projection restored | Trace attributes limited to operation/event type/HTTP method/route; 3,501 log lines and 335 structured boundary lines had zero banned private-key strings; repair returned `:repaired` at revision 4, live cumulative repair/drift counters appeared | `/tmp/hammerfall-phase13-final-telemetry-logs.log`, `/tmp/hammerfall-phase13-final-repair.log`; Tempo API inspection |
| Hosted CI implementation run | Push `701aad6d882c34e4eb912244cdde92c83080025a`, [run 36864158904](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36864158904) | API, web and Compose jobs all succeeded; Compose included Redis/Kafka/auction smokes and 7/7 real Chrome scenarios in 2.0 minutes. No observability-profile CI step exists; the optional stack was verified locally. | GitHub Actions run/jobs and Compose job log |

## Final adversarial review (local build)

No new Critical or High Phase 13 defect was found. The final trace has one
HTTP root and later child spans across transport boundaries; every parent ID
is present, and the HTTP span lasts 46.8 ms rather than waiting for consumers.
Kafka metadata stays in headers and consumer commits still follow effects.
Telemetry wrapper errors remain contained; the outage campaign showed correct
proxy outcomes and drained outboxes. Current Prometheus series use cumulative
`_total` counters and second-based duration histograms. No ID-bearing metric
label keys or raw routes appeared. The dashboard has no synthetic zero on
missing series, and descriptions distinguish broker/queue/server signals from
consumer effects and browser receipt. No Phase 14, auth or Kubernetes work was
introduced.

Medium/Future limits retained: external delivery still holds an outbox row lock
and database connection; collector outage evidence is not saturation/capacity
evidence; Kafka lag can be stale; per-process `service.instance.id` can churn
across restarts; the Ruby metrics SDK is alpha; no alert/SLO policy exists.
Phase 14 owns capacity measurement and Phase 15 owns any publisher redesign
if evidence warrants it. These are not Phase 13 correctness failures.

## Finalization disposition

| Item | Disposition | Evidence / limit |
|---|---|---|
| Backend, gated Kafka, static/security and frontend gates | COMPLETE | Finalization Evidence Index above |
| Normal and observability Compose runtime, full-stack smokes, real browser | COMPLETE | Finalization Evidence Index above |
| Traces, metric semantics, privacy, cardinality and dashboard review | COMPLETE | Finalization Evidence Index and `docs/observability.md` |
| Collector/storage outage behavior and bounded backpressure | COMPLETE | Session 2 campaign and final unchanged exporter config; not a capacity claim |
| Kafka lag freshness and browser receipt measurement | INTENTIONALLY LIMITED | Sampled broker position and server broadcast only; contract/runbook state limits |
| Load/capacity, SLO/alerts and publisher delivery redesign | DEFERRED WITH OWNER | Phase 14 capacity, Phase 15 publisher design; future operations policy |
| Hosted GitHub Actions on implementation code | COMPLETE | Run 36864158904, all three jobs green; final documentation-only commit is separately checked |
| Phase 14 implementation | NOT APPLICABLE | Explicitly excluded from Phase 13 |
