# Current handoff — Phase 9 primary outbox checkpoint

Updated: 2026-09-30. **Phase 9 — Transactional Outbox is active, not complete.** Resume from [the active ExecPlan](../plans/phase-09-execplan.md) and [Phase 9 specification](../phases/phase-09.md) following the [context lifecycle](../context-lifecycle.md). Phase 10 has not begun.

## Current state

- Phase 8 was complete before this session. Rails/PostgreSQL remains auction, deadline, proxy, winner, public revision and idempotency authority. Sidekiq/Redis carries public invalidations; Cable hints contain only type, auction ID and current revision. The read-only reconciliation sweep is unchanged.
- The precise Phase 8 loss window was `auction/idempotency COMMIT → after_commit callback → Sidekiq perform_async`. A crash or Redis failure after commit and before enqueue left no durable intent and could permanently lose the hint.
- Phase 9 primary implementation now inserts one `auction.changed.v1` outbox row, keyed by auction/public revision, **inside** `Auction#persist_public_change!` and the same PostgreSQL transaction/savepoint as the public mutation. An enclosing idempotency transaction also commits the command outcome. Rollback removes both state and intent. Private-only and unchanged commands produce no public row; replay produces no new row.
- A separate `outbox-publisher` Compose role polls due rows with `FOR UPDATE SKIP LOCKED`, enqueues the existing `AuctionChangedJob`, then acknowledges the row. Failed enqueue persists exponential retry state. Multiple publishers can reorder rows, and an unknown/failed acknowledgment can duplicate enqueue; the existing job's current-revision check makes duplicate/out-of-order hints harmless. The outbox acknowledges Sidekiq enqueue, **not** final Cable delivery. No exactly-once claim.

## Evidence and remaining work

Test database migration succeeded. Focused real-PostgreSQL specs passed: **22 examples, zero failures**, seed 52519. Focused RuboCop: **10 files, zero offenses**. The specs cover nested rollback, independent-reader invisibility, outbox insert failure rolling back bid/idempotency claim, replay, private-only changes, publisher retry, duplicate enqueue after ack failure and concurrent skip-locked claims. These are in-process tests; real process crash, Redis outage/recovery, sabotage, metrics observation and full regression remain.

Next session should inspect the [ExecPlan evidence index](../plans/phase-09-execplan.md), run live publisher/worker/Redis failure and recovery scenarios, review timeout and delivery limits, perform sabotage and broad regression, then update ADR/architecture/invariants/runbook/learning/code map/progress and this handoff. Finalize coherent commits and leave a clean tree only when the Phase 9 definition of done is met. No Kafka or Phase 10 work.
