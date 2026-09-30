# ADR-012: Disposable Redis public projection

Status: Accepted — Phase 11, 2026-09-30

## Context

The PostgreSQL auction row and committed public outbox already define authoritative
state and a durable Kafka publication intent. A Redis read can serve a compact
public snapshot, but publisher concurrency, Kafka replay, Redis loss and broker
retention prevent treating arrival order or Redis contents as auction truth.

## Decision

The separate `hammerfall.projection.v1` Kafka group validates the Phase 10 v1
envelope and writes its public `data` to one Redis key per auction:
`hammerfall:auction-public:v1:<auction_id>`. The value contains schema version,
auction ID, `public_revision`, event ID (null for a database seed), occurrence
time, Redis write time, source (`kafka` or `postgresql_seed`), the exact public
snapshot and its SHA-256 digest. It contains no private maximum, priority,
origin or idempotency material.

A Redis Lua operation compares and writes atomically. Higher revisions replace
lower ones; lower revisions are stale; equal revisions with equal public data
are duplicates; equal revisions with different data are conflicts and stop the
consumer without committing its Kafka offset. The consumer commits its offset
synchronously only after the Redis operation succeeds. A crash after the write
can replay the event as a duplicate. This is idempotent processing, not
exactly-once delivery.

`GET /api/v1/auctions/:id/public-state` is an explicit eventual read with
revision, source and age metadata and `Cache-Control: no-store`. Missing,
malformed or unavailable Redis state falls back to a current PostgreSQL
public-only response with `meta.source=postgresql`. The existing auction GET
and every command continue to use PostgreSQL. Redis is never consulted to
accept a bid, set a price/deadline/winner or resolve an idempotency outcome.

The operator can manually seed all auction keys from current PostgreSQL using
`bin/rebuild_auction_projections`. The same revision comparison protects a
newer key from an older seed or replay. A seed is a *current state* snapshot,
not a fabricated historical event. Kafka retention, pre-Phase-10 rows and
poison records make Kafka-only reconstruction insufficient. There is no
scheduled projection comparison or repair in Phase 11.

## Consequences and limits

Redis may be stale indefinitely if the publisher or consumer stalls. The
reported age is time since the represented event, not a promise of freshness.
Database fallback restores an authoritative read when Redis is absent or
unavailable, but does not automatically detect a well-formed stale key.
Consumer poison, same-revision conflicts and corrupt Redis values need
operator investigation; a corrupt key can block both replay and seeding until
it is removed. Full Redis loss requires a PostgreSQL seed unless complete
retained Kafka history is independently established. A single local Redis and
Kafka broker establish no production capacity, durability or HA claim.

## Alternatives

- Silently replace the ordinary auction GET with a cache: rejected because it
  would weaken its existing PostgreSQL observation contract.
- Let Redis decide command legality or close auctions: rejected because the
  projection is asynchronous and disposable.
- Rebuild only from Kafka: rejected because finite retention, legacy rows and
  poison events cannot guarantee complete current state.
- Add periodic drift repair now: deferred to Phase 12's separate scope.
