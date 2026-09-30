# Phase 9 ExecPlan — transactional outbox

Status: ACTIVE — primary implementation checkpoint, 2026-09-30; Phase 9 is **not complete**.
Current milestone: Live failure evidence, sabotage and full regression in a fresh session.
Completed: Inspected Phase 8 commit → enqueue loss window; created outbox migration/model, moved public intent write into locked domain transaction, removed post-commit enqueue, added independent publisher executable/Compose role, updated existing specs and added focused integration specs.
Verified: Real PostgreSQL migration and 22 focused examples, zero failures (seed 52519); focused RuboCop 10 files, zero offenses.
Remaining: Live Redis/process failure and recovery tests, backlog/metrics check, temporary sabotage, full regression/lint/browser/Compose startup, adversarial review, ADR and durable docs, final evidence/progress/handoff, coherent final commits.
Known failures/limitations: No live operational evidence yet. The outbox acknowledgment is successful Sidekiq enqueue, not final Cable delivery; Sidekiq Dead-set exhaustion or subsequent Redis loss can still lose the hint. Queue transport timeout is not bounded in code and needs review. No exactly-once delivery claim.
Relevant files: `apps/api/app/models/{auction,outbox_event}.rb`, `app/services/{auction_publication,outbox_publisher}.rb`, `app/jobs/auction_changed_job.rb`, `bin/outbox_publisher`, new migration/schema, outbox/public revision/job specs, Compose.
Relevant ADRs: ADR-009; a Phase 9 ADR will record publisher semantics.
Next-session starting point: Read `AGENTS.md`, latest handoff, Phase 9 spec and this plan. Inspect current diff/commit, then run real Compose publisher/Redis/worker fault scenarios before full regression and docs. Do not start Phase 10.

## Objective and boundary

For each public revision, write a public-only, versioned outbox row in the **same PostgreSQL transaction** as the auction mutation, including any accepted Bid, deadline, winner, and idempotency outcome transaction that encloses it. The row must disappear on rollback. No `COMMIT → outbox INSERT` path. Private-only maximum changes, unchanged commands, rejections and idempotency replays create no public row. Kafka remains Phase 10.

An independent publisher polls committed rows and enqueues `AuctionChangedJob`. PostgreSQL remains auction authority. Redis/Sidekiq/Cable failure affects freshness only. A publisher crash before enqueue leaves the row pending; crash after enqueue before marking published allows duplicate jobs. A successful Sidekiq enqueue acknowledges *publication to the queue*, not Cable delivery. Duplicate/reordered jobs and downstream broadcasts remain harmless via current-revision reads and REST recovery. No exactly-once claim.

## Decisions to validate

1. `auction.changed.v1` is the Phase 9 outbox event, with stable event ID, auction ID, public revision, schema version, occurrence time and no private payload. Unique `(auction_id, revision)` prevents duplicate intent. Phase 10 domain-event families are not introduced early.
2. Publisher uses small `FOR UPDATE SKIP LOCKED` batches, holds only outbox-row locks during a bounded enqueue attempt, marks a row published only after enqueue acknowledgment, and retries failures with persisted backoff. Multiple publishers may process different rows concurrently; same-auction delivery may reorder, which the existing job tolerates. Document DB/Redis timeout and capacity limits.
3. Backlog count, oldest pending age, due count and retry count are observable without exposing private or high-cardinality data. Operational recovery is repeatable; pending rows do not depend on a post-commit callback to become discoverable.

## Implemented transaction and publisher behavior

`Auction#persist_public_change!` increments `public_revision`, saves auction state, then calls `OutboxEvent.record_auction_change!` before its `requires_new` transaction/savepoint exits. An enclosing idempotency transaction commits the command outcome with both. Rollback at either level removes domain and outbox changes. Rows contain stable UUID, `auction.changed.v1`, schema version 1, auction ID, public revision, DB occurrence time and retry/ack fields; there is no private payload. Unique `(auction_id, public_revision)` defends intent identity. Initial auction creation remains revision zero and does not emit a hint; private-only/unchanged commands emit none.

`OutboxPublisher` polls due committed rows with PostgreSQL `FOR UPDATE SKIP LOCKED`, one row transaction at a time, then calls `AuctionChangedJob.perform_async(auction_id, public_revision)` and marks `published_at` only after an enqueue job ID. Enqueue errors persist class-only `last_error`, attempt count and exponential delay capped at 300 seconds; retries are indefinite. A crash before enqueue leaves the row pending. A crash or DB failure after enqueue before ack rolls back the acknowledgment and may enqueue twice. Multiple publisher processes may reorder different rows of the same auction; `AuctionChangedJob` reads current revision and broadcasts a repeatable public hint. No row is inserted after domain commit. Publisher logs aggregate backlog/due/retries/oldest-age metrics per cycle.

## Evidence required

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Atomic commit/rollback and replay | `bundle exec rspec spec/integration/public_revision_spec.rb spec/jobs/auction_changed_job_spec.rb spec/integration/transactional_outbox_spec.rb` | 22 examples, 0 failures; seed 52519 | Includes independent PostgreSQL reader, failed insert rollback and replay |
| Publisher concurrency/duplicate/retry | Same focused command | Passed | Skip-locked two-publisher claim, enqueue failure/backoff, ack-failure duplicate |
| Crash after commit/before enqueue | Separate process or equivalent real infrastructure fault | Pending; focused pending-row assertion only | Pending live proof |
| Crash after enqueue/before ack | Controlled fault and real queue/worker where feasible | In-process acknowledgment exception passed; live proof pending | `transactional_outbox_spec.rb` |
| Redis outage and recovery | Compose/live infrastructure | Pending | Pending |
| Backlog metrics | Focused and live check | Pending | Pending |
| Sabotage | Exact temporary mutant, expected failure and restoration | Pending | Pending |
| Focused lint | `bundle exec rubocop` on 10 changed Ruby files | 10 inspected, 0 offenses | Terminal output at checkpoint |
| Full regression/lint/local startup | `scripts/check`, Compose and relevant browser/independent process checks | Pending | Pending |

## Progress and unresolved items

- [x] Implement schema, transactional outbox write and publisher role.
- [x] Repair Phase 8 specs for asynchronous publication and add focused outbox tests.
- [ ] Run failure injection, sabotage and full regression; inspect concurrency/privacy/recovery adversarially.
- [ ] Update ADR, architecture, invariants, runbook, API/operational docs as changed, progress, learning guide, code map and handoff; commit coherently.
