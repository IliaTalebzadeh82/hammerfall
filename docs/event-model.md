# Event model

No events, outbox, publisher, broker, or consumers exist in Phase 0.

Phase 9 must commit outbox records atomically with domain state. Phase 10 introduces
versioned event schemas and at-least-once delivery with idempotent consumers.
Schema fields and compatibility rules will be documented alongside actual code;
private automatic-bid maxima must never leak into public events.
