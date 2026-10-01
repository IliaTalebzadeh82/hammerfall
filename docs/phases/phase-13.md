# Phase 13 — Observability

Status: Complete; verified locally and in hosted CI on 2026-10-01.

## Goal

Deliver the roadmap's observability scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 12 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [operations-and-security](../architecture/operations-and-security.md), [async-events](../architecture/async-events.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Add:

- OpenTelemetry
- Collector
- Prometheus
- Grafana
- Tempo
- structured logging
- dashboards

Ensure trace propagation across:

```text
HTTP
Sidekiq
Kafka
```

where practical.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

Retain the original metric examples as a design checklist: bid requests,
accepted/rejected by bounded reason, bid processing and auction lock wait
duration, extensions, close lag, pending/oldest outbox age and publish failures,
Kafka consumer lag, projection drift/repair and WebSocket delivery lag. Candidate
names are `hammerfall_bid_requests_total`, `hammerfall_bid_accepted_total`,
`hammerfall_bid_rejected_total{reason}`,
`hammerfall_bid_processing_duration_seconds`,
`hammerfall_auction_lock_wait_duration_seconds`,
`hammerfall_auction_extensions_total`, `hammerfall_auction_close_lag_seconds`,
`hammerfall_outbox_pending_events`,
`hammerfall_outbox_oldest_event_age_seconds`,
`hammerfall_outbox_publish_failures_total`,
`hammerfall_kafka_consumer_lag`, `hammerfall_projection_drift_total`,
`hammerfall_projection_repair_total` and
`hammerfall_websocket_delivery_lag_seconds`. Keep user/auction/bid/email IDs
out of unbounded labels. Dashboards should answer auction bid rate/latency/
rejections/close lag/extensions; messaging backlog/publish latency/failures/lag;
consistency drift/repair/failure/stale age; and runtime HTTP/DB/job health.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Verify traces across HTTP, Sidekiq and Kafka where practical; inspect metric cardinality, privacy, dashboards and failure instrumentation. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not claim dashboards prove correctness or leak private values/IDs in metric labels. Do not start Phase 14 without an explicit request.
