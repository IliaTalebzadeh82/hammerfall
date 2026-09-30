# Current handoff — Phase 9 complete

Updated: 2026-09-30. **Phase 9 — Transactional Outbox is complete.** Phase 10
has not begun and needs an explicit request. Read [ADR-010](../adr/010-transactional-public-outbox.md),
the [Phase 9 ExecPlan](../plans/phase-09-execplan.md) and [progress](../progress.md)
for the design, Evidence Index and actual verification.

## Current state

- Rails/PostgreSQL remains auction, deadline, proxy, winner, public revision and
  idempotency authority. Sidekiq/Redis and Cable carry public invalidations;
  browser REST reads authoritative state. The read-only reconciliation sweep is
  unchanged. No Kafka, projection or domain-event consumer exists.
- Each public mutation writes auction state, revision and a public-only
  `auction.changed.v1` outbox row inside one PostgreSQL transaction. The outer
  idempotency transaction also owns the command outcome. Rollback removes state
  and intent; replay, private-only, rejected and no-op commands add no event.
- The independent publisher claims due rows with `FOR UPDATE SKIP LOCKED`,
  enqueues `AuctionChangedJob`, then acknowledges successful enqueue. Failed
  attempts persist backoff and aggregate backlog metrics. Redis network calls
  have a two-second timeout; retry/acknowledgment/age use PostgreSQL clock time.
  Multiple publishers can reorder and duplicate jobs. The job reads current
  revision, so those hints remain safe. Acknowledgment is **queue enqueue**, not
  Cable or browser delivery. No exactly-once or fixed-latency claim.

## Evidence and limits

The primary implementation is commit `5a032e6`. A real originating Rails process died after
commit and another publisher found its pending rows. Real Redis loss left bids
committed and backlog retryable; restoration drained it. Killing a publisher
after Redis enqueue but before PostgreSQL acknowledgment produced two completed
jobs without changing auction truth. Concurrent PostgreSQL connections proved
same-row exclusion and different-row progress. Sabotage A–D detected or safely
handled the intended failures; all temporary mutants were restored.

Final local regression passed 368 backend examples, 90 RuboCop files, Brakeman,
Zeitwerk, 73 frontend tests and production build. Compose reported eight healthy
services. Real Playwright passed 7/7 with installed system Chrome; concurrent,
proxy, sequential, two-process idempotency, two-process Cable and multi-process
closing smoke passed. Bundler audit found no vulnerabilities. Hosted CI was not
run. The pinned browser CDN returned HTTP 403 in this location.

Redis loss after outbox acknowledgment, Sidekiq Dead-set exhaustion, Cable loss
or a connected browser missing a hint can still leave a stale view until REST
recovery. Poison rows retry indefinitely and require operators. No production
capacity, backup or fixed delivery-time evidence exists. The repository is ready
for a separately requested Phase 10, with these limits retained.
