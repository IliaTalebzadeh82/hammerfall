# Background work and domain events

## Status and responsibilities

This is a future contract. Phase 7 has no Redis, Sidekiq, outbox, Kafka or domain-event consumers. Current Cable `auction.changed.v1` is an ephemeral public invalidation, not a durable domain event. [Event model](../event-model.md) and [failure model](../failure-model.md) must be updated as each phase lands.

## Phase 8: jobs and Redis

Use Sidekiq/Redis for application jobs: notification work, scheduled reconciliation scaffolding, cleanup and operational maintenance. Every job must tolerate retries; side effects that can duplicate need idempotency. Define duplicate, delayed, failed and reordered work, bounded retries and operator recovery. Redis can support ephemeral reads, presence or rate limiting, but never decides accepted bids or winners. Its total loss must leave PostgreSQL auction truth intact. Do not conflate Sidekiq jobs with Kafka domain-event propagation or claim the queue closes the commit/enqueue gap.

## Phases 9–10: outbox and Kafka

For a durable event-producing domain mutation, insert an OutboxEvent in the same PostgreSQL transaction as the auction/bid change. Never treat a separate DB write followed by direct Kafka publish as atomic. A publisher may retry after crash, broker outage or unknown acknowledgment, so events need stable IDs, aggregate order/version, retry state and bounded operational recovery. Rollback leaves neither state change nor event; commit preserves both.

Use explicit versioned schemas such as `bid.accepted.v1`, `auction.extended.v1`, `auction.closed.v1`, `auction.won.v1`. Define event ID/type/schema version/aggregate ID/version or sequence/occurred_at/relevant payload and trace context when appropriate. Do not expose private maxima unnecessarily. Kafka is propagation, not auction authority. Consumers for projection, notification or append-only audit must tolerate duplicates, restart, replay, poison records and ordering gaps. Prefer honest at-least-once semantics; do not claim exactly once without proof. Document schema compatibility and consequences before publishing.

## Failure semantics

Kafka outage should leave authoritative bidding available while outbox backlog grows and derived state becomes stale; recovery drains it. Crash after DB commit should retain the outbox row. Consumer crash/replay may re-deliver, with idempotent downstream effects. Sidekiq/Redis outages may delay jobs/notifications but must not change auction correctness. Test these paths with real infrastructure when feasible; record what is unavailable, stale, correct and how recovery occurs.
