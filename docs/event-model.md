# Event model

Phase 9 implements a PostgreSQL outbox for one public invalidation type. No
Kafka broker or domain-event consumers exist. Sidekiq jobs are application
work, not Kafka events. Phase 10 may add domain-event schemas and consumers.

Each `outbox_events` row contains `event_id` (stable UUID), `event_type`
(`auction.changed.v1`), `schema_version` (1), `auction_id`, `public_revision`,
`occurred_at` (database transaction timestamp), `next_attempt_at`, `attempts`,
`last_error` (class only) and `published_at` (successful queue enqueue). Retry,
acknowledgment and pending-age clocks are read from PostgreSQL. The
unique `(auction_id, public_revision)` key gives one intent per public version.
There is no private payload. A new incompatible schema needs a new version and
consumer review; the current database constraint admits only version 1.

## Public invalidation — Phases 7–9

The current wire message is exactly type=auction.changed.v1, auction_id, revision.
It is an ephemeral public invalidation, not a durable business event. Lifecycle,
proxy contests and soft-close changes all use the same hint; REST supplies meaning.
Phase 9 persists the public ID/revision intent inside the mutation transaction.
The independent publisher enqueues the existing job later; the job reads current
PostgreSQL revision and broadcasts the same Cable hint. Redis failure before
enqueue keeps the row pending, but Redis loss after acknowledgment or worker/Cable
failure may still lose the hint. Retry can duplicate it. No Kafka topic or
domain-event replay has been introduced.
