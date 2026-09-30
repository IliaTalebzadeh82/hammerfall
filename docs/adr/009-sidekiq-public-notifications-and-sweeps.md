# ADR-009: Redis-backed public notifications and read-only sweeps

Status: Accepted — Phase 8, 2026-09-30

## Context

Phase 7 publishes public revision invalidations directly through PostgreSQL Action Cable after commit. Phase 8 requires Redis, Sidekiq, application jobs, a notification pipeline and a scheduled reconciliation framework. The product has no authenticated identities or private notification channels. PostgreSQL must still decide every bid, price, deadline and winner. Outbox durability belongs to Phase 9.

## Decision

Keep the PostgreSQL Action Cable adapter and exact `{type:"auction.changed.v1",auction_id,revision}` public protocol. `AuctionPublication.after_commit` still attaches to the outermost Rails transaction, but its callback now enqueues `AuctionChangedJob` with only scalar auction ID and revision. Enqueue failure is logged by class and public identifiers without raising into an already committed command. No Redis call occurs inside the domain transaction. There is a commit-to-enqueue gap and Redis/queue/worker loss can prevent a hint permanently.

`AuctionChangedJob` reads the current PostgreSQL public revision, rejects impossible future revisions, and broadcasts the current revision. A delayed or reordered job therefore cannot send a lower revision than current state. Duplicate jobs may repeat a harmless public hint; the browser ignores equal/stale revisions and GETs REST for authority. Missing auction rows are skipped. A Cable/DB failure raises into Sidekiq's bounded five-retry policy and then its Dead set; job execution never mutates auction state or resolves a client intention. The runtime uses `notifications` and `maintenance` queues, with two job threads and a three-connection default DB pool. No user-specific email or private maximum data is sent.

A separate scheduler enqueues `ReconciliationSweepJob` every 60 seconds by default, with a minimum five-second configured interval. It is an advisory process role; multiple schedulers may duplicate work without changing authority. A one-shot mode exits nonzero on enqueue failure. The job snapshots an upper auction ID, scans bounded 100-row batches, and chains the next cursor. Each SQL statement reads auction state and latest accepted bid together via an indexed lateral lookup. It logs only auction ID and a fixed drift kind when current price/latest bid, leader/latest bidder or closed winner/leader disagree. It does not repair PostgreSQL or compare a Redis projection; Phase 12 owns projection drift and repair. Redis/DB errors trigger bounded Sidekiq retry; repeated scans can report the same drift.

Redis is a job transport with local AOF/volume, not auction authority or a promise of durable domain events. The API can boot and accept bids without Redis. Queue state is operational, not a substitute for an outbox. The scheduler and worker are separate Compose roles; the existing independent auction closer is unchanged.

## Alternatives considered

- Keep direct Cable publication and add a dummy notification job: fails to make Sidekiq do meaningful notification work.
- Switch Cable itself to Redis: adds another transport dependency and changes a previously verified cross-process adapter without a concrete requirement. Retained PostgreSQL adapter was reverified through API A and Cable B with the worker active.
- Enqueue within the auction transaction: a worker could announce rolled-back/uncommitted state, and Redis latency would hold the hot auction lock.
- Persist notification ownership in PostgreSQL now: that is the Phase 9 outbox and is expressly excluded.
- Cron extension or leader election: unnecessary for an idempotent read-only sweep; the small scheduler uses one local process role and does not claim exact cadence or singleton execution.
- Repair detected PostgreSQL drift automatically: the checker lacks a trustworthy correction source for an inconsistent authoritative database and should not guess.

## Consequences and risks

The notification path is now `COMMIT → enqueue → worker → PostgreSQL Cable → REST GET`, adding queue delay and Redis/worker availability. A crash after commit but before enqueue, a failed enqueue, lost Redis data, exhausted retries or a failed broadcast can lose a hint. A continuously connected browser may remain stale until its existing recovery trigger. A queued hint can become redundant, duplicate or out of order; no exactly-once claim exists. Sidekiq job data contains no private fields, but Redis operators can inspect public auction IDs/revisions. No queue throughput or capacity benchmark exists.

Runbooks must inspect notification/maintenance queues, retries, Dead set, Redis health and worker logs. Safe manual retry of an existing job is allowed; fabricating missed revisions from browser history is not. An operator can force a fresh browser GET or investigate PostgreSQL state. The read-only sweep reports potential corruption and requires human investigation; repeated logs are expected until resolved.

## Revisit when

Phase 9 adds transactional outbox reliability; Phase 10 adds domain events; Phase 11–12 introduce a Redis projection and actual drift repair. Reconsider the Cable adapter only with measured connection/fanout evidence and independent-process verification. Authentication is required before private/user-specific notifications. Review Redis persistence, high availability, connection budgets, scheduler cadence and operations before production.

Sidekiq references: [best practices](https://github.com/sidekiq/sidekiq/wiki/Best-Practices), [error handling](https://github.com/sidekiq/sidekiq/wiki/Error-Handling), [Redis configuration](https://github.com/sidekiq/sidekiq/wiki/Using-Redis), and [recurring schedule limitations](https://github.com/sidekiq/sidekiq/wiki/Scheduled-Jobs).
