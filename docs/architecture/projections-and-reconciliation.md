# Read models, consistency and repair

## Current consistency

PostgreSQL is the single persisted authority. At Phase 8, the browser renders REST observations that can become stale; separate auction and bid-history requests are not one snapshot. Public revisions order observations, but queued Cable hints can still be lost. There is no Redis auction projection or projection drift repair. A scheduled read-only PostgreSQL checker compares auction rows with the latest accepted Bid and logs discrepancies; it is not a derived-state reconciler. See [consistency model](../consistency-model.md) and [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md).

## Planned projection contract

Introduce a Redis auction read model only for a measured read/fanout need. A projection must carry aggregate version/sequence and freshness metadata; it cannot supersede PostgreSQL for bidding, deadline or winner decisions. Redis loss and replay must be recoverable from authoritative data/events. Out-of-order or duplicate events must not regress projection state. A fast read should disclose staleness or fall back under a documented degradation policy.

## Planned reconciliation

A scheduled checker should compare derived state to PostgreSQL by explicit fields/version, detect drift, repair safe cases idempotently and flag cases needing operator action. It should expose drift, repair and repair-failure counts and structured repair logs without sensitive values. Tests must deliberately corrupt projections and prove convergence and failure behavior. Document comparison scope, automatic-repair boundary, replay/duplicate behavior, stale-age visibility and operator runbook. Read-model inconsistency must be both detectable and repairable; `docs/failure-model.md` should state what stays correct, unavailable or stale during Redis/Kafka/worker failures.
