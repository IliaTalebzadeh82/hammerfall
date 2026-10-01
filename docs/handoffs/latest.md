# Current handoff — Phase 13 active, session 1 checkpoint

Updated: 2026-10-01. Phase 12.5 remains complete at
`41bff7c9d8ca4cc8ccec9f012541fe772c9bace0`; its 424 backend, 3 live
Kafka, 73 frontend and 7 browser tests plus hosted run 36845095870 passed.
Phase 13 Observability was explicitly requested. Do not begin Phase 14.
Read `AGENTS.md`, [Phase 13](../phases/phase-13.md), the
[active ExecPlan](../plans/phase-13-execplan.md), and targeted context via the
[map](../context-map.md). The ExecPlan Evidence Index is the session 1 proof.

Session 1 defined the [telemetry contract](../observability.md) and added an
optional Collector/Prometheus/Tempo/Grafana Compose profile with provisioned
data sources. Rails now has bounded, fail-open OTLP SDK setup, safe HTTP route
tracing, bid request/outcome/duration and auction lock wait/extension/close
metrics, domain/DB/outbox spans and correlated JSON bid logs. PostgreSQL
authority, transaction/lock order, idempotency and event identity were not
redesigned.

Focused OTel-enabled tests passed 54 examples with the Collector endpoint
unreachable, followed by 43 examples after privacy/route review. Targeted
RuboCop, Zeitwerk and both Compose configurations passed. An OTel-enabled
Compose API passed the proxy smoke, including concurrent maxima. Both
Prometheus scrape targets were up; actual counter/histogram series had bounded
labels and expected seconds buckets. Tempo showed an HTTP maximum command
trace across lock, decision, proxy, PostgreSQL save and outbox persistence,
and honored a supplied W3C parent. Grafana health and provisioned Prometheus
and Tempo data sources returned successfully. Details and log paths are in the
ExecPlan.

Next: inspect the existing outbox/publisher/consumer contracts and add
privacy-safe Sidekiq/Kafka context propagation and async metrics. Then
instrument projection/reconciliation/Cable, add dashboards, inspect live
series/traces and run the mandatory telemetry outage campaign. Full
backend/frontend/browser/Compose/hosted CI and final docs/adversarial review
remain. The dashboard directory is provisioned but currently empty.

Retained limits: the API is an unauthenticated demo and unsafe for public
exposure. Publishers still hold outbox locks and DB connections through
external delivery. Collector startup logs one misleading optional-namespace
error in pinned v0.136.0, but actual export and scraping work. Ruby OTel
metrics SDK is alpha. No capacity claim, production monitoring SLA or full
Phase 13 outage proof exists yet.
