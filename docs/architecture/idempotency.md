# Client command idempotency

## Responsibility and scope

Protected HTTP manual-bid and maximum commands use `Idempotency-Key` as a stable client intention. Internal Auction operations and the closer do not automatically have this contract. The server scopes a versioned HMAC digest of the key to authenticated actor/operation, fingerprints the semantic payload, and claims a PostgreSQL unique record before touching Auction. Retained legacy SHA-256 rows remain available for replay.

## Atomicity and replay

One outer transaction owns logical-key advisory lock, key claim, domain savepoint, mutation and stored safe terminal HTTP status/body. Thus commit makes both mutation and outcome durable, and rollback makes the key retryable. A concurrent duplicate waits on the logical-key lock and unique claim; matching completed requests replay the original public response without rechecking auction state, clock or lock, even after later closure. A changed payload with the same scoped key returns 409 without executing. Replay is historical outcome, not current auction state; clients refresh current GETs afterward.

Terminal 200/201 and expected 404/422 outcomes are retained. Missing/invalid key, malformed preclaim input and actor failures are not retained; unexpected/DB failures roll back, not cached as 500. No committed `processing` row is expected on the normal path. Lock order is logical-key advisory lock, idempotency ownership, then auction. Raw keys and maximums stay out of logs and public snapshots.

## Retention and limits

Default seven-day DB-time expiry means prune eligibility, not automatic key reuse. A present row reserves its key; bounded completed-row pruning makes reuse possible. Old HMAC keys remain configured until every row written with them is physically pruned. Do not shorten retention without considering client retry horizons or destroy retained outcomes during rollback. The browser stores one unresolved key/payload in tab session storage before sending, explicitly retries it after ambiguity, and uses a one-hour conservative retry horizon. API snapshot migration, pruning operations and multi-region writes need future design.

[ADR-006](../adr/006-client-command-idempotency.md) is canonical for exact fingerprint, status, privacy, pruning and collision semantics. [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md) owns digest versioning and rotation. [ADR-007](../adr/007-browser-command-intentions.md) owns client behavior. Implementations are [Executor](../../apps/api/app/services/idempotency/executor.rb) and [intentions](../../apps/web/src/lib/intentions.ts).
