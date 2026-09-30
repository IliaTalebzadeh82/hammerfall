# Current handoff — Phase 11 complete

Updated: 2026-09-30. **Phase 11 — Redis Projection is complete.** Phase 12 has
not started and requires a separate explicit request. The
[Phase 11 ExecPlan](../plans/phase-11-execplan.md) is the durable Evidence Index
and adversarial review; [progress](../progress.md) records the phase outcome.

## Implemented boundary

PostgreSQL owns auction state and commands. The committed public outbox feeds
Kafka; the independent `hammerfall.projection.v1` consumer validates v1 public
events, atomically applies only a higher revision to disposable Redis, then
commits its Kafka offset. Equal public data is duplicate, lower revision is
stale, and equal-revision different data stops the consumer. The explicit
`/api/v1/auctions/:id/public-state` endpoint is eventual and falls back to
PostgreSQL on a missing, malformed or unavailable Redis key. Ordinary GET,
bidding, idempotency, deadlines and winner decisions remain PostgreSQL-backed.
`bin/rebuild_auction_projections` manually seeds current public state after
Redis loss. No scheduled Redis drift repair was added.

## Verification and limits

Implementation commits: `b88ad58` and `25c7172`. Finalization added ADR-012,
architecture/API/failure/runbook and learning documentation plus a Redis service
to the API CI job. The full backend suite passed 389 examples; Ruby lint,
Brakeman, bundler-audit, 73 frontend tests, frontend lint/format/types/build,
Compose rebuild/startup, runtime smokes and 7 real browser scenarios passed.
Live Redis outage, total projection loss, PostgreSQL rebuild, stale/duplicate
replay, consumer crash/replay, privacy and four sabotages are recorded in the
ExecPlan. Hosted CI itself was not run.

The projection can remain stale, and valid stale keys do not trigger fallback.
Kafka retention and pre-Phase-10 rows cannot guarantee full replay. Poison
offsets, corrupt keys and Redis total loss need operator review/rebuild.
No exactly-once processing, bounded freshness or replay time, production
capacity or Redis/Kafka HA is claimed. The local API remains unauthenticated.

## Next boundary

If Phase 12 is explicitly requested, begin from its specification, this
handoff and the Phase 11 ExecPlan. Its scope is projection drift detection
and repair; do not reinterpret the existing read-only PostgreSQL sweep as
Redis reconciliation.
