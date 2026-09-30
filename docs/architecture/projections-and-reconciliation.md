# Read models, consistency and repair

## Current consistency

PostgreSQL is the single auction authority. The browser renders REST observations that can become stale; separate auction and bid-history requests are not one snapshot. Public revisions order observations, but queued Cable hints can still be lost. Phase 10's Kafka audit is append-only metadata. Phase 11 adds a disposable Redis public projection through a separate Kafka group; its explicit eventual endpoint falls back to PostgreSQL on miss, corruption or outage. A scheduled read-only PostgreSQL checker compares auction rows with the latest accepted Bid and logs discrepancies; it is not a derived-state reconciler. See [consistency model](../consistency-model.md) and [ADR-012](../adr/012-redis-public-projection.md).

## Phase 11 projection contract

`hammerfall.projection.v1` consumes committed public Kafka v1 snapshots into `hammerfall:auction-public:v1:<auction_id>`. Each value includes the public revision, source, event/write times, public data and digest. An atomic Redis revision check rejects stale replay and equal-revision conflicts; equal content is a duplicate. The explicit `/public-state` GET discloses Redis source and age or uses PostgreSQL fallback. Existing GET and commands remain PostgreSQL-backed. Operators can manually rebuild current state from PostgreSQL; no automatic freshness bound or drift repair is promised. See [the runbook](../runbooks/redis-projection.md).

## Planned reconciliation

A scheduled checker should compare derived state to PostgreSQL by explicit fields/version, detect drift, repair safe cases idempotently and flag cases needing operator action. It should expose drift, repair and repair-failure counts and structured repair logs without sensitive values. Tests must deliberately corrupt projections and prove convergence and failure behavior. Document comparison scope, automatic-repair boundary, replay/duplicate behavior, stale-age visibility and operator runbook. Read-model inconsistency must be both detectable and repairable; `docs/failure-model.md` should state what stays correct, unavailable or stale during Redis/Kafka/worker failures.
