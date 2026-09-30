# Phase 8 ExecPlan — Sidekiq, Redis and non-authoritative jobs

Status: COMPLETE — started and verified 2026-09-30. Scope ended before Phase 9.

## Objective and boundaries

Implement Sidekiq/Redis, a useful public notification job pipeline, and scheduled reconciliation scaffolding. Keep auction acceptance, price, deadline, winner, idempotency outcome and public revision in PostgreSQL transactions. Preserve the three-field Cable message and REST recovery. No outbox, Kafka, Redis auction projection, repair engine or public user notification channel.

## Decisions to validate

1. Retain the PostgreSQL Action Cable adapter and existing public channel. After the outermost commit, enqueue a Sidekiq job carrying only auction ID/revision. The job checks current public revision and broadcasts a revision hint; duplicate, delayed and reordered jobs are harmless. Enqueue/worker failure must be logged without changing a committed domain/idempotency result. Explicitly document the commit-to-enqueue loss window.
2. Add a bounded read-only PostgreSQL consistency sweep. It checks persisted auction price against the latest accepted Bid and final winner against current leader, reporting detected mismatches without mutation. A separate periodic scheduler enqueues sweeps; overlapping jobs are safe. Projection drift/repair is reserved for Phase 12.
3. Use bounded Sidekiq retries, separate queues and Redis connection settings. Provide local Compose worker, scheduler and Redis services plus one-shot operational commands. Redis is an availability dependency for hints/jobs, never for bid legality.
4. Keep test-mode dispatch deterministic for existing committed-publication specs, then add focused real-Redis/worker integration and failure injection. Any adapter change requires independent Rails-process proof; the adapter is not changing.

## Work sequence

- [x] Commit the pre-existing context migration separately (`63edbb8`).
- [x] Add dependency/runtime configuration, job classes, publication handoff, read-only sweep and scheduler (`f2d59cd`).
- [x] Add focused tests for commit boundary, duplicate/stale/out-of-order hints, privacy, Redis/worker failure, retry/recovery and sweep behavior.
- [x] Run focused tests; inspect and repair one test expectation error.
- [x] Run actual Compose Redis/worker checks, fault injection and cross-process browser/HTTP proof.
- [x] Run full backend/frontend/browser/security/build regression, Docker verification and adversarial review.
- [x] Update ADR/architecture/failure, operations, invariants, learning/code map, progress and handoff with actual evidence. Documentation completion is the final Phase 8 commit.

## Verification record

Final focused specs: 19 examples, zero failures. Native `scripts/check` ran before
two final spec additions: 357 backend examples, 73 frontend tests, RuboCop,
Brakeman, Zeitwerk, lint/format/types and production build passed. Final full
container RSpec after those additions: 359 examples, zero failures. Targeted
RuboCop passed; bundler-audit found no vulnerabilities. Real-API Playwright passed
7/7 in 1.6 minutes. Compose built and started all seven roles. Independent API
A/Cable B script passed through Sidekiq with revision 2 → 3 → REST 3.

Worker-stop backlog grew 0 → 3 while a real bid committed, then drained after
restart. Redis-stop bid and exact idempotent replay succeeded with an enqueue
failure log; API restart without Redis succeeded and accepted another bid.
Scheduler one-shot failed nonzero during outage and succeeded after restoration.
A deliberately impossible revision entered the real Sidekiq RetrySet and its test
job was removed. Three temporary mutant runs each produced their expected targeted
failure; no mutation remains. Final test database fixture counts were all zero.
See [progress](../progress.md#phase-8--sidekiq--redis) for exact IDs and limits.

Adversarial review checked transaction timing, replay, public-only payloads,
duplicate/reordered jobs, retry/dead behavior, read-only sweep, Redis-independent
API startup, browser recovery, and Phase 9 exclusion. No authoritative business
decision moved to Redis or Sidekiq. Remaining delivery loss, scheduler cadence,
Redis persistence/HA, authentication and capacity limits are documented in
[ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md), the [runbook](../runbooks/sidekiq-redis.md)
and [handoff](../handoffs/latest.md). Hosted CI was not run: this repository has
no remote. No throughput/capacity benchmark was performed.
