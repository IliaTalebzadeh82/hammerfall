# Background work and domain events

## Status and responsibilities

Phase 8 now runs Redis, Sidekiq notification/maintenance jobs and a read-only
scheduled PostgreSQL sweep. There is still no outbox, Kafka, Redis auction
projection or domain-event consumer. Cable `auction.changed.v1` remains an
ephemeral public invalidation, not a durable domain event. See [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md),
[event model](../event-model.md) and [failure model](../failure-model.md).

## Phase 8: jobs and Redis

After the outer commit, `AuctionPublication` enqueues `AuctionChangedJob` with
public auction ID and revision only. It reads current PostgreSQL revision before
broadcasting through the existing PostgreSQL Cable adapter. Duplicate, delayed
and reordered jobs may repeat a harmless current hint; the browser still GETs
REST. Queue/worker/Cable failure cannot change a committed domain or idempotency
result. A failed enqueue can permanently lose a hint. Sidekiq retries a failed
job five times before the Dead set; no exactly-once or guaranteed delivery claim
is made.

`ReconciliationScheduler` periodically enqueues bounded
`ReconciliationSweepJob` batches. The job compares the authoritative auction
price/leader/final winner with the latest accepted Bid in one SQL statement and
logs drift without changing rows. Overlap and retries are safe. There is no
Redis projection yet to reconcile or repair. Redis may later support ephemeral
reads, presence or rate limits, but never decide a bid or winner. Sidekiq jobs
are distinct from future Kafka domain-event consumers. See the [runbook](../runbooks/sidekiq-redis.md).

## Phases 9–10: outbox and Kafka

For a durable event-producing domain mutation, insert an OutboxEvent in the same PostgreSQL transaction as the auction/bid change. Never treat a separate DB write followed by direct Kafka publish as atomic. A publisher may retry after crash, broker outage or unknown acknowledgment, so events need stable IDs, aggregate order/version, retry state and bounded operational recovery. Rollback leaves neither state change nor event; commit preserves both.

Use explicit versioned schemas such as `bid.accepted.v1`, `auction.extended.v1`, `auction.closed.v1`, `auction.won.v1`. Define event ID/type/schema version/aggregate ID/version or sequence/occurred_at/relevant payload and trace context when appropriate. Do not expose private maxima unnecessarily. Kafka is propagation, not auction authority. Consumers for projection, notification or append-only audit must tolerate duplicates, restart, replay, poison records and ordering gaps. Prefer honest at-least-once semantics; do not claim exactly once without proof. Document schema compatibility and consequences before publishing.

## Failure semantics

Kafka outage should leave authoritative bidding available while outbox backlog grows and derived state becomes stale; recovery drains it. Crash after DB commit should retain the outbox row. Consumer crash/replay may re-deliver, with idempotent downstream effects. Sidekiq/Redis outages may delay jobs/notifications but must not change auction correctness. Test these paths with real infrastructure when feasible; record what is unavailable, stale, correct and how recovery occurs.
