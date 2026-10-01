# Projection reconciliation operations

PostgreSQL owns auction truth. Redis stores a disposable public projection;
reconciliation compares it with PostgreSQL and repairs only unambiguous
missing/lower-revision keys. The scheduler triggers maintenance and does not
participate in bidding. See [ADR-013](../adr/013-bounded-reconciliation-scan-ownership.md)
and the [projection recovery runbook](redis-projection.md).

## Inspect a suspected drift

Compare the ordinary PostgreSQL-backed `GET /api/v1/auctions/:id` with the
explicit eventual `GET /api/v1/auctions/:id/public-state`. Compare
`public_revision` and the public fields, including status, price, leader,
winner and deadlines; source/age metadata is diagnostic. A valid stale key is
possible between scans. Do not infer an accepted bid from the Redis endpoint.

In local Compose, inspect health, recent scheduler/worker logs and the durable
lease rows:

```sh
docker compose ps db redis sidekiq reconciliation-scheduler kafka-projection-consumer
docker compose logs --tail=100 --no-color reconciliation-scheduler sidekiq
docker compose exec -T api bin/rails runner 'puts ApplicationRecord.connection.select_all("SELECT name, cursor, expires_at, clock_timestamp() AS db_now FROM reconciliation_leases ORDER BY name").to_a'
```

Rails' `auction_projection_reconciliation` entries include auction ID,
result, drift kind and error class; never log a raw projection or private
bidder fields. `auction_projection_reconciliation_metrics` records report
`checked`, `healthy`, drift, attempt, repair, repair failure, unavailable and
operator-review counts for **one batch**. The `_batch` field names are
per-batch deltas. Exported `hammerfall_projection_*_total` series are actual
cumulative process counters. Aggregate those series by time window without
using auction/event IDs as metric labels.

## Expected outcomes

| Redis observation | Action |
| --- | --- |
| Equal revision and identical public fields | Healthy; no write. |
| Missing key | Seed current PostgreSQL public state through the atomic writer. |
| Valid lower revision | Seed the current PostgreSQL revision; intermediate replay is not required. |
| Equal revision with different public fields | Preserve key and request operator review. |
| Ahead of freshly reloaded PostgreSQL revision | Preserve key and request operator review. |
| Malformed envelope or bad digest | Preserve key and request operator review. |
| Redis or PostgreSQL unavailable | Raise/retry; never guess a repair from Redis. |

An old repair racing a newer Kafka delivery returns `raced` and cannot lower
the key. The reverse order advances when Kafka later delivers. Two
reconcilers may duplicate an attempt without corrupting state.

## Restore service and scheduled progress

For Redis outage, restore Redis first. PostgreSQL bidding and ordinary GET
should have continued. Sidekiq retries can resume; the next scheduled scan
repairs missing or valid lower-revision keys. For PostgreSQL outage, restore
the database before running any comparison. Check Sidekiq Retry/Dead sets and
logs for exhausted jobs, then trigger a one-shot scheduled scan if needed:

```sh
docker compose exec -T reconciliation-scheduler bin/reconciliation_scheduler --once
```

Each scheduled scan type has one PostgreSQL lease. A second scheduler tick
reports `already_active` while its chain progresses. Each job checks at most
100 ID-ordered rows under a fixed maximum ID and hands off its token/cursor
to the next page. The final page releases its lease. A dead owner or missing
continuation leaves the lease for at most ten minutes after its last renewal;
a later tick reclaims it and restarts at ID zero. Inspect `expires_at` against
PostgreSQL `db_now` before treating a row as abandoned. Do not delete a live
lease or infer auction state from it. A manual tokenless job invocation is
uncoordinated and may overlap with a scheduled scan; prefer the one-shot
scheduler command for routine recovery.

If an equal-conflicting, ahead or corrupt key persists, preserve the key and
relevant PostgreSQL/outbox evidence for review. Confirm the authoritative
public row and Kafka history before any targeted intervention. A corrupt key
may require deletion of only `hammerfall:auction-public:v1:<auction_id>` and
reseed after review, as detailed in the projection recovery runbook. Never
alter an auction row, bid, outbox event or idempotency record to make Redis
look healthy. No fixed convergence time or exactly-once execution is promised.
