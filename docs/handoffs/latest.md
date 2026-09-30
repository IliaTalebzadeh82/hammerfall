# Current handoff — Phase 12 complete

Updated: 2026-10-01. Phase 12 reconciliation is complete. Phase 13 and the
separate post-Phase-12 hardening pass have not started; each needs an explicit
request. Use `AGENTS.md`, the requested phase specification and
[context map](../context-map.md) for future work. This handoff and the
[Phase 12 ExecPlan](../plans/phase-12-execplan.md) carry the completed state
and detailed Evidence Index.

PostgreSQL remains the only auction authority. `AuctionProjectionReconciler`
compares its public revision and fields against validated Redis state, seeds
missing/lower-revision keys through the atomic writer, and leaves
equal-conflicting, corrupt or ahead keys for operator review. Equal identical
state is a no-op. The existing PostgreSQL consistency sweep remains read-only
and separate. Each scheduled scan checks at most 100 ID-ordered rows per job.
PostgreSQL leases with token/cursor fencing prevent ticks, multiple schedulers
and Sidekiq replay from multiplying scan chains; expiry restarts abandoned
work from ID zero. Neither the lease nor Redis participates in bids.

Commits `ceb3d04` and `3b7e64f` contain the primary implementation and live
campaign; `6f8f94b` adds bounded scheduled ownership. The live campaign
verified real Kafka race orderings, concurrent reconcilers, outages, crash
recovery, corruption/review and four successful sabotage experiments. Final
backend regression: 410 examples, 0 failures, 2 explicitly gated live Kafka
examples pending; RuboCop 108 files/0 offenses, Brakeman 0 warnings,
bundler-audit no vulnerabilities and Zeitwerk passed. Frontend lint, format,
types, production build and 73 Vitest tests passed. Compose startup, service
health, scheduler/Kafka/API/concurrent/proxy/publisher/closer smokes passed.
Real Playwright with installed system Chrome passed 7/7 after a browser test
waited for the asynchronous Cable hint. Hosted CI was not run.

Limits: valid stale Redis state can persist until a successful scan; ambiguous
states require operator review. A lost page handoff can delay until the
ten-minute lease expires. Per-batch structured log counts are not exported
Prometheus counters. No fixed convergence time, production capacity, HA or
real-money readiness is claimed. The demo API remains unauthenticated. See
[ADR-013](../adr/013-bounded-reconciliation-scan-ownership.md) and the
[runbook](../runbooks/projection-reconciliation.md) for ownership and recovery.
