# Event model

Phase 10 extends the committed PostgreSQL public outbox with separate Kafka
delivery state and a public domain snapshot. Sidekiq jobs are application work,
not Kafka events. See [ADR-011](adr/011-kafka-domain-events.md).

Each `outbox_events` row retains the Phase 9 `event_id` (stable UUID),
`event_type` (`auction.changed.v1`), `schema_version` (1 for retained rows,
2 for new reserve-capable snapshots), `auction_id`,
`public_revision`, `occurred_at` (PostgreSQL wall time at outbox insertion), Sidekiq retry
fields and `published_at` (successful queue enqueue). The unique
`(auction_id, public_revision)` key gives one intent per public version.
The outbox `schema_version` describes its Kafka domain snapshot; the Cable
invalidation type stays `auction.changed.v1` for both values.
Phase 10 adds `domain_event_type`, `domain_payload`, `kafka_next_attempt_at`,
`kafka_attempts`, `kafka_last_error` and `kafka_published_at`. Sidekiq and Kafka
acknowledgments are independent. Phase 9 rows without historical domain
snapshots were marked Kafka-acknowledged by migration, not fabricated.
Historical rows inserted before Phase 12.5 retain their original transaction-start
`occurred_at`; the migration changes the default for new rows only. Auction
`decision_time` is sampled after its row lock for eligibility/closure. Event
occurrence follows the auction mutation and is not commit time. Retry scheduling
defaults may use transaction start; publisher acknowledgment timestamps are
sampled after delivery, and Redis `projected_at_ms` is Redis write time. None
of these timestamps orders bids or replaces the auction-local sequence.

Normal Active Record updates cannot change a committed event's identity, type,
revision, public payload or occurrence time. Publisher retry and acknowledgment
fields remain mutable. The database admits only known domain types and object
payloads for new snapshots; old invalidation-only rows remain valid.

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
`schema_version` (1 or 2), `aggregate_id` (auction ID), `aggregate_version` (public
revision), `occurred_at`, and `data`. Data is a public snapshot of title,
description, status, starting price, minimum increment, starts_at,
original_ends_at, current price, current leader ID, ends_at, closed_at and
winner ID. Version 2 adds `reserve_status` (`none`, `not_met`, `met`), never the
reserve amount. There is no private maximum, priority, bid origin, raw client key
or trace payload.

The exact v1 domain types are `auction.status_changed.v1`,
`auction.terms_changed.v1`, `auction.price_changed.v1`, `auction.extended.v1`
and `auction.closed.v1`. One revision has one event. A price event may also
carry a changed deadline. Existing v1 fields and meanings are immutable.
Phase 21 adds matching `.v2` domain types and schema version 2 in the same
topic. Consumers validate retained v1 with its exact old fields/winner rule;
all new events use v2. Consumers reject unknown versions, types, keys or fields
instead of silently advancing offsets.

`PublicAuctionSnapshot` validates the same public field set for Kafka decoding
and Redis projection reads, including amount bounds,
`starts_at < original_ends_at <= ends_at`, closure
metadata and version-specific winner/leader consistency. A v2 closed snapshot
may retain a leader without a sale winner only when `reserve_status` is `not_met`.
A semantically impossible snapshot is
poison or a corrupt projection and requires review; it is not repaired by
inventing another event envelope.

Kafka records can be duplicated or reordered because PostgreSQL publisher
claims are concurrent. `aggregate_version` and event ID, rather than broker
offset, identify the public state transition. The audit consumer stores one
receipt and public metadata entry per event, classifies first, next, gap and
stale arrivals, and never decides an auction outcome. Retention is broker
policy; replay is bounded by retained data and does not backfill pre-Phase-10
historical events.

## Phase 11 projection consumer

The independent `hammerfall.projection.v1` group validates both versions.
Retained v1 events normalize to `reserve_status=none`; the v2 projection key
`hammerfall:auction-public:v2:<auction_id>` holds only public v2 data and
freshness metadata. Old v1 Redis keys are ignored and current state is seeded
from PostgreSQL when missing. The group keeps its offsets and commits after
the Redis write. Redis revision comparison makes repeat
and reordered events safe; equal-revision conflicting public data stops the
group. This derived state is neither another domain event nor auction
authority. See [ADR-012](adr/012-redis-public-projection.md).
