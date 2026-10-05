# Read models, consistency and repair

## Current consistency

PostgreSQL is the single auction authority. The browser renders REST observations that can become stale; separate auction and bid-history requests are not one snapshot. Public revisions order observations, but queued Cable hints can still be lost. Phase 10's Kafka audit is append-only metadata. Phase 11 adds a disposable Redis public projection through a separate Kafka group; its explicit eventual endpoint falls back to PostgreSQL on miss, corruption or outage. A scheduled read-only PostgreSQL checker compares auction rows with the latest accepted Bid and logs discrepancies; it is not a derived-state reconciler. See [consistency model](../consistency-model.md) and [ADR-012](../adr/012-redis-public-projection.md).

## Phase 11 projection contract

Retained v1 events normalize to `reserve_status=none` and
`closing_policy=regular`. Earlier v2 events without a closing policy also
normalize to `regular`; new v2 events and PostgreSQL rebuilds carry the
persisted policy.

`hammerfall.projection.v1` consumes committed public Kafka v1 and v2 snapshots into `hammerfall:auction-public:v2:<auction_id>`. Retained v1 events are normalized to `reserve_status=none`; old v1 Redis keys are ignored. Each value includes the public revision, source, event/write times, public data and digest. An atomic Redis revision check rejects stale replay and equal-revision conflicts; equal content is a duplicate. The explicit `/public-state` GET discloses Redis source and age or uses PostgreSQL fallback. Existing GET and commands remain PostgreSQL-backed. Operators can manually rebuild current state from PostgreSQL; no automatic freshness bound or drift repair is promised. See [the runbook](../runbooks/redis-projection.md).

## Phase 12 reconciliation

`AuctionProjectionReconciler` compares the PostgreSQL auction's
`public_revision` and exactly the public `KafkaEventCodec::DATA_KEYS`
presenter fields with a strictly validated Redis projection. Source, event
ID and write time are metadata, not part of public-state equality. A present
key whose public fields violate `PublicAuctionSnapshot` is corrupt, even if its
stored digest matches; Kafka decode uses the same semantic field contract.
An absent key or valid lower revision is seeded from current PostgreSQL through the
existing atomic Redis revision/digest script. An equal, identical key is
healthy without mutation. Equal-revision conflicting data, a malformed or
digest-invalid key, and a Redis revision ahead of a freshly reloaded
PostgreSQL row require operator review. Redis never corrects PostgreSQL.

The atomic write rejects an old repair after a newer Kafka projection has
arrived; the reverse order advances normally when Kafka later delivers.
Repeated repair and concurrent reconcilers may do duplicate work, but cannot
regress the key. A repair is a current-state seed, not replay of intermediate
history or an exactly-once event. Redis or PostgreSQL outage raises for
Sidekiq retry and leaves auction truth unchanged. Valid stale Redis reads can
persist until a scheduled scan; no finite freshness bound is promised. See
[ADR-013](../adr/013-bounded-reconciliation-scan-ownership.md), the
[consistency model](../consistency-model.md), [failure model](../failure-model.md)
and [reconciliation runbook](../runbooks/projection-reconciliation.md).

The existing PostgreSQL consistency sweep remains read-only and separate.
Both scheduled scan types use 100-row ID-ordered pages under a fixed maximum
ID ceiling. A PostgreSQL maintenance lease per type prevents periodic ticks
from starting overlapping chains. Each page renews a database-clock lease;
only one attempt can advance its cursor and enqueue a successor. A crash or
lost continuation eventually lets the lease expire, after which a new scan
starts at ID zero. A manual unleased job may overlap by operator choice.
The scheduler is a maintenance trigger, never an auction correctness boundary.
