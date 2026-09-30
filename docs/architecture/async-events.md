# Background work and domain events

## Status and responsibilities

Phase 9 runs a PostgreSQL transactional outbox and an independent publisher,
alongside Redis, Sidekiq notification/maintenance jobs and a read-only sweep.
There is no Kafka, Redis auction projection or domain-event consumer. Cable
`auction.changed.v1` remains a public invalidation. See [ADR-010](../adr/010-transactional-public-outbox.md), [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md),
[event model](../event-model.md) and [failure model](../failure-model.md).

## Phase 8: jobs and Redis

Historically, after the outer commit, `AuctionPublication` enqueued
`AuctionChangedJob`; Phase 9 replaced that callback with the durable outbox.
The job reads current PostgreSQL revision before
broadcasting through the existing PostgreSQL Cable adapter. Duplicate, delayed
and reordered jobs may repeat a harmless current hint; the browser still GETs
REST. Queue/worker/Cable failure cannot change a committed domain or idempotency
result. A failed enqueue now leaves the outbox row pending. Sidekiq retries a failed
job five times before the Dead set; no exactly-once or guaranteed delivery claim
is made.

`ReconciliationScheduler` periodically enqueues bounded
`ReconciliationSweepJob` batches. The job compares the authoritative auction
price/leader/final winner with the latest accepted Bid in one SQL statement and
logs drift without changing rows. Overlap and retries are safe. There is no
Redis projection yet to reconcile or repair. Redis may later support ephemeral
reads, presence or rate limits, but never decide a bid or winner. Sidekiq jobs
are distinct from future Kafka domain-event consumers. See the [runbook](../runbooks/sidekiq-redis.md).

## Phase 9: public outbox

`Auction#persist_public_change!` writes the revision and an `OutboxEvent` under
the existing auction lock and transaction. An enclosing idempotency transaction
also owns the terminal command outcome. A rollback removes state and intent;
private-only changes and replay create no row. A separate process claims due
committed rows with `FOR UPDATE SKIP LOCKED`, enqueues the existing Sidekiq job,
and then acknowledges enqueue. Failed attempts remain pending with persisted
backoff. Multiple publishers can advance different rows concurrently, including
different revisions of one auction; no global delivery order is promised.

The event is a versioned public invalidation with stable UUID, auction ID,
revision and occurrence time. It contains no private maximum, priority, bid
origin or key. Acknowledgment says Redis accepted the job, not that Cable or a
browser received it. Duplicate enqueue and reordered jobs remain possible and
safe for current-revision invalidations. See [the event model](../event-model.md)
and [the runbook](../runbooks/sidekiq-redis.md).

## Phase 10: future Kafka domain events

Kafka-specific domain events remain a separate phase. Future consumers must use
committed outbox intent without moving auction decisions into the broker.

Use explicit versioned schemas such as `bid.accepted.v1`, `auction.extended.v1`, `auction.closed.v1`, `auction.won.v1`. Define event ID/type/schema version/aggregate ID/version or sequence/occurred_at/relevant payload and trace context when appropriate. Do not expose private maxima unnecessarily. Kafka is propagation, not auction authority. Consumers for projection, notification or append-only audit must tolerate duplicates, restart, replay, poison records and ordering gaps. Prefer honest at-least-once semantics; do not claim exactly once without proof. Document schema compatibility and consequences before publishing.

## Failure semantics

Today a Redis outage leaves authoritative bidding available while outbox backlog
grows; restoring Redis and the publisher drains due rows. A process crash after
commit retains the row. A crash after enqueue but before acknowledgment can
duplicate a job. Redis loss after acknowledgment or exhausted worker retries
can still lose the hint; REST recovery remains necessary. Kafka outage and
consumer replay behavior are future Phase 10 work.
