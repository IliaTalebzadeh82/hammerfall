# ADR-011: Kafka downstream of the public outbox

Status: Accepted — Phase 10, 2026-09-30

## Context

Phase 9 commits an `auction.changed.v1` outbox row with each public revision and
dispatches a Sidekiq/Cable invalidation asynchronously. Kafka must carry
versioned domain events without creating a second post-commit loss window or
making broker availability part of an auction command.

## Decision

Each new public outbox row also stores one public domain event type and immutable
public snapshot in the **same PostgreSQL transaction** as the auction mutation,
revision and command outcome. The existing Sidekiq publisher and `published_at`
remain intact. Independent `kafka_*` attempt, retry and acknowledgment fields
belong to a second publisher. Legacy Phase 9 rows are marked Kafka-acknowledged
by migration because their historical domain snapshots cannot be reconstructed.

The dedicated publisher claims due rows with `FOR UPDATE SKIP LOCKED`, sends the
stored envelope to `hammerfall.auction-events.v1` using the auction ID as the
partition key, waits for the broker delivery report (`acks=all`, idempotent
producer), then sets `kafka_published_at` using PostgreSQL time. A failed or
ambiguous send stays pending with an exponential retry capped at 300 seconds.
The database lock covers the send and acknowledgment. Multiple publishers may
send different revisions of one auction out of order; no global order claim is
made. The three-partition count is fixed for this topic version; increasing it
can remap an auction key and needs a reviewed migration. A crash after broker delivery but before database acknowledgment can
publish the same event ID again. Kafka acknowledgment means broker acceptance,
not consumer processing or future retention.

The v1 envelope has `event_id`, `event_type`, `schema_version`, `aggregate_id`,
`aggregate_version`, `occurred_at` and `data`. The data is a public state
snapshot: public terms, status, price, leader ID, end time, close time and winner ID. Types
are `auction.status_changed.v1`, `auction.terms_changed.v1`,
`auction.price_changed.v1`, `auction.extended.v1` and `auction.closed.v1`.
When price and deadline change together, the price event includes the new
deadline. There is no private maximum, priority, bid origin, raw idempotency
key or bidder maximum. New incompatible schemas require a new event/topic
version and consumer review; v1 consumers reject unknown shape and version.

The initial consumer group `hammerfall.audit.v1` writes a receipt and an
append-only public metadata audit entry in one PostgreSQL transaction. It stores
and synchronously commits the Kafka offset **after** the transaction commits.
A duplicate event ID is an acknowledged no-op. The audit entry classifies
arrival as first, next, gap or stale; it does not update auction state. An
invalid envelope or failed database side effect does not commit the offset.
Poison records stop the consumer and require operator diagnosis, correction or
an explicit replay/reset decision. The group starts at earliest when no offset
exists. Separate future consumer groups own their own receipts and effects.

## Consequences and limits

PostgreSQL remains the only auction authority. Kafka, its publisher and its
consumer can fail while bids and the Sidekiq/Cable path continue. Broker
retention and a single-node local broker do not form a backup. Producer retries,
publisher crashes and consumer offset ambiguity mean at-least-once delivery;
the receipt protects this consumer's database side effect. It is not a general
exactly-once guarantee. Reordered records can be audited without regressing
auction truth. The two publishers claim the same outbox table row, so a slow
Kafka send can briefly delay Sidekiq's claim for that row; it cannot hold the
auction lock or change a command. Phase 11 projection work is not introduced here.

## Alternatives

- Direct Kafka publish after the API commit: reintroduces a process-crash loss
  window, so rejected.
- Make Kafka the transaction coordinator or auction authority: violates the
  current lock, clock and command protocols, so rejected.
- Replace the Sidekiq/Cable outbox delivery: would change Phase 9 freshness
  behavior and couples the browser path to broker availability, so rejected.
- Invent historical domain events from current auction rows: would mislabel
  old state as historical fact, so rejected.
