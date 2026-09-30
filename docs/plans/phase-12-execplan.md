# Phase 12 ExecPlan — projection reconciliation

Status: Active; primary implementation checkpoint, 2026-10-01.
Current milestone: Live corruption, recovery, concurrency, outage and sabotage campaign in a fresh session.
Completed: Inspected Phase 11 authority/projection path; implemented `AuctionProjectionReconciler`, bounded `AuctionProjectionReconciliationJob`, scheduler enqueue and focused tests. The preexisting read-only PostgreSQL sweep remains separate. This milestone changed no authoritative command, Kafka or projection write code.
Verified: 14 focused RSpec examples, 0 failures, seed 59735; RuboCop 5 files, 0 offenses; `git diff --check` clean. Real local PostgreSQL/Redis were used by the integration examples. These are focused checks, not the live outage campaign or final regression.
Remaining: Live deliberate corruption/repair and operator-review cases; Redis/PostgreSQL outages, concurrent Kafka delivery/multiple reconcilers, duplicate/crash recovery and bounded scan proof; sabotage and adversarial review; broad regression, Compose/runtime/security/build/browser checks required by scope; ADR/runbook/architecture/invariants/failure/observability/learning/code-map/progress updates; final handoff and clean commits. Do not start Phase 13.
Known failures/limitations: No failing focused check remains. The current metrics are named counters in per-batch structured logs, not a Prometheus endpoint; document this equivalent and evaluate operational visibility in the live campaign. Corrupt/equal-conflict/ahead keys require operator review; no automatic overwrite. Phase 11's valid stale reads until a scheduled scan, poison offset and finite Kafka retention remain.
Relevant files: `apps/api/app/services/{auction_public_projection,auction_projection_reconciler,reconciliation_scheduler,kafka_projection_consumer}.rb`, `app/jobs/{auction_projection_reconciliation_job,reconciliation_sweep_job}.rb`, `spec/integration/{auction_projection_reconciliation,redis_projection}_spec.rb`, `spec/jobs/reconciliation_sweep_job_spec.rb`.
Relevant ADRs: [ADR-012](../adr/012-redis-public-projection.md); record the adopted Phase 12 policy in a new ADR during documentation finalization.
Next-session starting point: Read this plan, handoff and Phase 12 spec; inspect changed source/tests. Start the live campaign with disposable auction keys, record exact commands/results/logs, then checkpoint again if broad regression/docs remain. No live failure scenario has yet been run.

## Decisions

- Authority: compare PostgreSQL `Auction.public_revision` and the exact `KafkaEventCodec::DATA_KEYS` public presenter fields against the validated Redis envelope. PostgreSQL is read independently of Redis; Redis never decides bidding, closure or winner.
- Drift model: missing and valid lower-revision keys are safe to seed from PostgreSQL. Equal revision with identical public data is healthy regardless of source/write time. Equal revision with different data, Redis ahead of PostgreSQL after a fresh check, and malformed/digest-invalid keys require operator review; do not silently overwrite them. Redis or PostgreSQL unavailability is reported and retried, not treated as drift.
- Repair uses the existing atomic Redis revision/digest Lua operation. It is safe against duplicate work and a concurrently delivered higher revision. A concurrent equal conflict is escalated. No global lock or auction row lock is needed for a derived-state snapshot; a later PostgreSQL change may make a just-written seed stale until Kafka delivery or the next scan.
- Keep the existing read-only PostgreSQL sweep distinct. The existing scheduler will enqueue a separate projection reconciliation chain; each job handles at most 100 ID-ordered rows under a fixed ceiling, then enqueues the next cursor. Counters are emitted per batch as bounded-cardinality structured log metrics with required metric names; Phase 13 can add a scraper/exporter.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Phase 11 path and authority | Targeted source, ADR-012, Phase 11 handoff and ExecPlan | Revision/digest Lua guard, PostgreSQL seed and explicit eventual read confirmed | `auction_public_projection.rb`, `kafka_projection_consumer.rb`, Phase 11 ExecPlan |
| Phase 12 focused tests | `bundle exec rspec spec/integration/auction_projection_reconciliation_spec.rb spec/jobs/reconciliation_sweep_job_spec.rb` | 14 examples, 0 failures, seed 59735 | `/tmp/hammerfall-p12-focused.log`; real local PostgreSQL/Redis |
| Focused Ruby lint | `bundle exec rubocop` on 5 changed Ruby files | 5 files, 0 offenses | `/tmp/hammerfall-p12-rubocop.log` |
| Whitespace | `git diff --check` | Clean | Local command 2026-10-01 |
| Live failure/corruption campaign | Pending | Unrun | — |
| Full regression/runtime | Pending | Unrun | — |

## Primary implementation checkpoint

The checker reads a PostgreSQL auction snapshot and validates the Redis envelope using the existing strict projection reader. It compares `public_revision` and every `KafkaEventCodec::DATA_KEYS` field, ignoring source/event/write metadata for equality. Missing and valid lower revisions call the existing PostgreSQL seed, whose atomic Redis Lua guard accepts only a higher revision or identical equal content. A concurrent higher write returns `stale`; a concurrent equal conflict is logged as repair failure and operator review. A same-revision public mismatch, malformed/digest-invalid key or key ahead of a freshly reloaded PostgreSQL row is logged for operator review without mutation. Redis failure raises for Sidekiq retry. PostgreSQL failure also raises and logs its error class. Neither path changes an auction row.

The scheduler now enqueues the old read-only PostgreSQL sweep plus the new projection scan. Projection jobs read up to 100 auctions in ID order under a fixed max-ID ceiling, emit per-batch structured JSON counters and enqueue the next cursor only after completing the batch. Counters use the required drift/repair/failure names plus attempted, checked, unavailable and operator review. Identifiers appear only in per-auction logs, never as metric labels. Repeated scheduler runs can overlap; the Redis atomic guard makes duplicate repairs safe. No global lock or bid-path dependency was added.

Focused integration tests deliberately create missing, stale, equal-content, equal-conflict, ahead, malformed and digest-corrupt keys, plus a conflict arriving between detection and seed. They cover idempotent repeat, stale replay rejection, Redis read outage, job metric counts and unchanged PostgreSQL state. Existing scheduler spec verifies both jobs are enqueued. Live multi-process, full outage and crash behavior remain to prove in the next milestone.
