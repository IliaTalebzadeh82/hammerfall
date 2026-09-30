# Background work and domain events

## Status and responsibilities

Phase 10 runs two independent publishers from the committed PostgreSQL outbox:
Sidekiq/Cable public invalidations and Kafka public domain events. A Kafka audit
consumer records receipt and side effect; no Redis auction projection exists.
Cable `auction.changed.v1` remains a public invalidation. See [ADR-011](../adr/011-kafka-domain-events.md), [ADR-010](../adr/010-transactional-public-outbox.md), [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md),
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
are distinct from Kafka domain-event consumers. See the [runbook](../runbooks/sidekiq-redis.md).

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

## Phase 10: Kafka domain events

The same public outbox insert stores one versioned public domain snapshot per
revision. `KafkaOutboxPublisher` claims committed rows, waits for an `rdkafka`
broker delivery report, then sets `kafka_published_at`. Its retry state is
independent of Redis acknowledgment. Topic `hammerfall.auction-events.v1` has
three local partitions, keyed by auction ID. Concurrent publisher claims can
still place revisions out of order. The initial `hammerfall.audit.v1` consumer
group validates v1 envelopes, writes a receipt and public audit entry in one
PostgreSQL transaction, then commits the Kafka offset. Duplicate IDs are
harmless; gaps and stale arrivals are classified. Poison events stop the
consumer at the uncommitted offset for operator review. See the [event model](../event-model.md),
[Kafka runbook](../runbooks/kafka.md) and [ADR-011](../adr/011-kafka-domain-events.md).

## Failure semantics

Redis outage leaves authoritative bidding available while Sidekiq outbox backlog
grows; restoring Redis and the publisher drains due rows. A process crash after
commit retains the row. A crash after enqueue but before acknowledgment can
duplicate a job. Redis loss after acknowledgment or exhausted worker retries
can still lose the hint; REST recovery remains necessary. Kafka outage leaves
Kafka outbox rows pending while Sidekiq/Cable can continue. After recovery the
publisher drains rows; crash ambiguity and consumer replay can duplicate events
without repeating the audit effect or changing auction truth.
