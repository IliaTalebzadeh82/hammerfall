# Current handoff — Phase 13 active, session 2 hard checkpoint

Updated: 2026-10-01. Phase 12.5 remains complete at `41bff7c`.
Phase 13 Observability is active; do not begin Phase 14. Read `AGENTS.md`,
[Phase 13](../phases/phase-13.md), the
[active ExecPlan](../plans/phase-13-execplan.md), and targeted context via the
[map](../context-map.md). The ExecPlan Evidence Index holds the exact checks,
logs, live trace IDs, limits and remaining work.

Session 1 (`76df52c`) established the passive Rails telemetry contract and
optional Collector/Prometheus/Tempo/Grafana stack. Session 2 added bounded
outbox W3C metadata, Sidekiq and Kafka context propagation, publisher and
consumer tracing, backlog/lag/worker/projection/reconciliation/Cable metrics,
structured async logs and a provisioned operations dashboard. The v1 Kafka
business envelope, public Sidekiq job args, PostgreSQL authority and offset
commit order remain intact. Development logs now use info level because debug
SQL inlined private maximum and priority values. Rails request logs also filter
whole command payloads; a live body-marker scan found no title/description text.

Focused async verification passed 69 examples, zero failures, with one opt-in
live Kafka example pending; targeted RuboCop, Zeitwerk and observability Compose
config passed. A live 19-span maximum command trace joined HTTP, outbox,
Sidekiq worker/Cable, Kafka audit and Redis projection. Real Prometheus series
had bounded labels; Grafana loaded 32 panels with 30 valid PromQL queries.
Collector, Prometheus, Tempo and Grafana outages kept proxy bidding correct and
both outboxes drained. Kafka and Redis outages showed pending/retry signals and
drained on recovery. Four reversible sabotage changes made the intended tests
fail, then were restored. Actual traces/logs/series were checked for privacy.

Next fresh session: run broad backend regression with test
`REDIS_URL=redis://redis:6379/1` while live development uses DB 0, then
frontend regression, static/security gates, full Compose/browser scenarios,
final telemetry inspection, hosted CI, runbook/progress completion and final
adversarial review. Repair failures and declare Phase 13 complete only after
those gates pass. Do not repeat the live outage campaign without a concrete
new risk.

Retained limits: this is an unauthenticated demo, not public-production-ready.
Publishers still hold PostgreSQL row locks/connections across external delivery.
Kafka lag gauges sample the broker only after committed messages and can go
stale for idle/dead consumers; inspect broker group offsets. Ruby OTel metrics
SDK is alpha. Collector v0.136.0 still logs one misleading optional-namespace
error although export and scraping work. The Collector outage was bounded local
evidence, not a load or queue-saturation claim. Broad regression, browser and
hosted CI have not run for the session 2 changes.
