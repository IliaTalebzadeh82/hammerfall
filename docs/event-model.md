# Event model

No events, outbox, publisher, broker, or consumers exist in Phase 0.

Phase 9 must commit outbox records atomically with domain state. Phase 10 introduces
versioned event schemas and at-least-once delivery with idempotent consumers.
Schema fields and compatibility rules will be documented alongside actual code;
private automatic-bid maxima must never leak into public events.

## Implemented Phase 7 invalidation

The current wire message is exactly type=auction.changed.v1, auction_id, revision.
It is an ephemeral public invalidation, not a durable business event. Lifecycle,
proxy contests and soft-close changes all use the same hint; REST supplies meaning.
No event log, outbox, Kafka topic or domain-event replay has been introduced.
