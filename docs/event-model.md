# Event model

Phase 10 extends the committed PostgreSQL public outbox with separate Kafka
delivery state and a public domain snapshot. Sidekiq jobs are application work,
not Kafka events. See [ADR-011](adr/011-kafka-domain-events.md).

Each `outbox_events` row retains the Phase 9 `event_id` (stable UUID),
`event_type` (`auction.changed.v1`), `schema_version` (1), `auction_id`,
`public_revision`, `occurred_at` (PostgreSQL transaction time), Sidekiq retry
fields and `published_at` (successful queue enqueue). The unique
`(auction_id, public_revision)` key gives one intent per public version.
Phase 10 adds `domain_event_type`, `domain_payload`, `kafka_next_attempt_at`,
`kafka_attempts`, `kafka_last_error` and `kafka_published_at`. Sidekiq and Kafka
acknowledgments are independent. Phase 9 rows without historical domain
snapshots were marked Kafka-acknowledged by migration, not fabricated.

## Public invalidation — Phases 7–10

The Cable wire message is exactly type=auction.changed.v1, auction_id,
revision. It requests a fresh REST GET; it is not a command acknowledgment or
durable event. The independent Sidekiq publisher enqueues a job from committed
outbox intent; the job reads current PostgreSQL revision. Redis failure before
enqueue keeps the row pending, but Redis loss after acknowledgment or worker/
Cable failure may still lose the hint. Kafka delivery does not replace it.

## Kafka public domain envelope — Phase 10

Topic `hammerfall.auction-events.v1` has three local partitions. Every record
uses the decimal auction ID as key, so one auction maps to one partition while
the partition count is fixed. The
JSON envelope has exactly `event_id` (stable outbox UUID), `event_type`,
`schema_version` (1), `aggregate_id` (auction ID), `aggregate_version` (public
revision), `occurred_at`, and `data`. Data is a public snapshot of title,
description, status, starting price, minimum increment, starts_at,
original_ends_at, current price, current leader ID, ends_at, closed_at and
winner ID. There is no private maximum, priority, bid origin, raw client key
or trace payload.

The exact v1 domain types are `auction.status_changed.v1`,
`auction.terms_changed.v1`, `auction.price_changed.v1`, `auction.extended.v1`
and `auction.closed.v1`. One revision has one event. A price event may also
carry a changed deadline. Existing v1 fields and meanings are immutable; an
incompatible shape requires a new type/schema/topic version and reviewed
consumer migration. Consumers reject unknown versions, types, keys or fields
instead of silently advancing offsets.

Kafka records can be duplicated or reordered because PostgreSQL publisher
claims are concurrent. `aggregate_version` and event ID, rather than broker
offset, identify the public state transition. The audit consumer stores one
receipt and public metadata entry per event, classifies first, next, gap and
stale arrivals, and never decides an auction outcome. Retention is broker
policy; replay is bounded by retained data and does not backfill pre-Phase-10
historical events.

## Phase 11 projection consumer

The independent `hammerfall.projection.v1` group validates this exact v1
envelope, writes only its public `data` plus version/freshness metadata to
Redis, then commits its Kafka offset. Redis revision comparison makes repeat
and reordered events safe; equal-revision conflicting public data stops the
group. This derived state is neither another domain event nor auction
authority. See [ADR-012](adr/012-redis-public-projection.md).
