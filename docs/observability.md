# Observability

Current diagnostics are framework/Sidekiq logs, Rails `/up`, Compose health checks,
Redis `PING`, queue/retry/Dead counts and test/lint output. These do not constitute
the planned observability system.

Phase 12 emits structured JSON reconciliation logs and per-batch count deltas:
`checked`, `healthy`, `auction_projection_drift_total`,
`auction_projection_repair_attempt_total`, `auction_projection_repair_total`,
`auction_projection_repair_failure_total`, `unavailable` and `operator_review`.
Despite the `_total` names, values in each log record describe that batch;
they are not process-lifetime Prometheus counters. Operators sum records for
an interval and inspect per-auction result/drift/error-class logs for review.
Auction IDs occur only in diagnostic logs, never metric labels. Scheduler
logs `enqueued` or `already_active` by fixed scan type. The
[reconciliation runbook](runbooks/projection-reconciliation.md) describes
inspection and recovery. Logs do not create a monitored freshness SLA.

OpenTelemetry, Collector, Prometheus, Grafana, Tempo, traces, exported metrics
and dashboards remain Phase 13 work. No measured production monitoring,
capacity or performance coverage is claimed.
