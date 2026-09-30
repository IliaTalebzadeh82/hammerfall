# Event model

No durable domain events, outbox, broker or domain-event consumers exist through
Phase 8. Phase 8 Sidekiq jobs are application work, not Kafka events.

Phase 9 must commit outbox records atomically with domain state. Phase 10 introduces
versioned event schemas and at-least-once delivery with idempotent consumers.
Schema fields and compatibility rules will be documented alongside actual code;
private automatic-bid maxima must never leak into public events.

## Implemented public invalidation — Phases 7–8

The current wire message is exactly type=auction.changed.v1, auction_id, revision.
It is an ephemeral public invalidation, not a durable business event. Lifecycle,
proxy contests and soft-close changes all use the same hint; REST supplies meaning.
Phase 8 enqueues a public ID/revision notification job after commit; the job reads
current PostgreSQL revision and broadcasts the same Cable hint. Redis/worker loss
can delay or lose it, and retries can duplicate it. No event log, outbox, Kafka
topic or domain-event replay has been introduced.
