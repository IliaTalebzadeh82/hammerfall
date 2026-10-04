# Redis public projection recovery

PostgreSQL is auction authority; Kafka transports committed public events;
Redis holds a disposable derived snapshot. The ordinary auction GET and all
commands use PostgreSQL. The explicit `/public-state` GET can be stale and
falls back to PostgreSQL on a missing, malformed or unavailable Redis value.
See [ADR-012](../adr/012-redis-public-projection.md).
Scheduled Phase 12 drift detection and safe repair are covered by the
[reconciliation runbook](projection-reconciliation.md); the manual rebuild
below remains available for deliberate operator recovery.

## Inspect

From the repository root:

```sh
docker compose ps db kafka kafka-outbox-publisher kafka-projection-consumer redis api
docker compose exec -T redis redis-cli ping
docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 --describe --group hammerfall.projection.v1
docker compose logs --tail=100 --no-color kafka-outbox-publisher kafka-projection-consumer redis api
```

Compare a known auction's ordinary `/api/v1/auctions/:id` GET with
`/api/v1/auctions/:id/public-state`: inspect `public_revision`, public fields,
`meta.source` and `meta.age_seconds`. A Redis result is only the last accepted
projection event. `projected_at` is the Redis write time;
`event_occurred_at` identifies the source change. Neither certifies current
PostgreSQL state. Avoid logging raw Redis values or private database records.

## Redis unavailable or lost

Confirm PostgreSQL commands and ordinary GETs still work. The eventual GET
should report `meta.source=postgresql`. Restore Redis and restart a stopped
consumer with `docker compose start redis kafka-projection-consumer`; inspect
consumer lag. A failed Redis write keeps its Kafka offset uncommitted, so the
consumer can retry. A previously committed offset does not replay merely
because Redis was lost. Seed current state from PostgreSQL:

```sh
docker compose exec -T api bin/rebuild_auction_projections
```

The script reports applied, duplicate and stale counts. Verify a sample of
public revisions and fields against the ordinary PostgreSQL GET. Keep the
consumer running or restart it afterward; older Kafka replay cannot lower a
seeded revision. Seeding does not erase unrelated Redis keys or Sidekiq queues.
Do not flush a shared Redis database merely to repair this namespace.

## Poison, conflict or corrupt key

An invalid Kafka envelope or equal-revision/different-data conflict stops the
projection consumer without offset commit. Review its partition, offset and
error class, the committed PostgreSQL row/outbox snapshot, and the retained
Kafka record in a protected environment. Do not reset an offset just to clear
lag. If a deliberate skip is warranted, stop this **projection group** and
preview/reset only the affected partition using the Kafka runbook's procedure
with group `hammerfall.projection.v1`; record the decision. Seed from PostgreSQL
after any skipped history.

A malformed Redis value makes the endpoint fall back, but can also make Lua
replay or seeding fail. After identifying the affected auction and preserving
diagnostic evidence, delete only
`hammerfall:auction-public:v2:<auction_id>` and run the PostgreSQL rebuild.
Never delete a PostgreSQL auction, outbox row or idempotency record to repair a
projection. Check consumer lag and the endpoint again.

## Limits

Phase 11 had no automatic drift detection or repair. Phase 12's scheduled
checker can repair valid stale keys after it scans them; a valid stale
projection remains a Redis response until a later event or successful scan.
Kafka retention and legacy rows prevent assuming full replay coverage. The
local single-node broker/Redis and observed campaign provide no fixed recovery
time, production capacity or HA assurance.
