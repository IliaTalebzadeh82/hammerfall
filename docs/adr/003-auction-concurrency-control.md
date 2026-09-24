# ADR-003: Serialize auction commands with a PostgreSQL row lock

Status: Accepted — Phase 2, 2026-09-24

## Context

Phase 1 wraps bid insertion and price update in a transaction, but reads without
locking. With current price 10000 and increment 500, A and B both reload 10000.
A validates 11000; B validates 10500. A inserts and commits price 11000. B inserts
and commits price 10500. Both transactions are individually atomic, but the price
regresses and B should have been rejected. Reload alone and savepoints do not
protect a read/check/write decision. Different Rails processes share this race.

## Decision

Use PostgreSQL READ COMMITTED transactions and SELECT FOR UPDATE on the auction
row, through `reload(lock: true)`. Acquire the lock before reading authoritative
state or inspecting bids. Then sample application time, validate status/window,
participants/amount and fresh minimum, assign auction-local sequence, insert Bid,
update stored current_price, and commit. Return HTTP success only after the command
transaction returns. Nested calls use savepoints: the outermost transaction owns
final durability and lock release. Callers must not report success before it commits.

Assign `sequence = MAX(sequence) + 1` (or 1 for an empty auction) under that lock.
A NOT NULL positive bigint and unique `(auction_id, sequence)` index protect the
stored ordering. No separate counter or global database sequence is necessary.
Committed bids through these commands start at 1 and are contiguous while history
is immutable; rejected/rolled-back attempts consume no sequence. The public promise
is unique, strictly increasing auction-local acceptance order, not a universal
no-gaps guarantee against privileged deletion or future changes. IDs and timestamps
are metadata, not ordering authority. Lock acquisition is not FIFO arrival order.

Existing draft edits and lifecycle commands take the same auction lock before
validation/winner selection. This coordinates current commands only; database clock
policy, closing workers, soft-close and distributed scheduling remain Phase 4.
No network work or retries occur inside the critical section. Ordinary commands
lock one auction first, then write bids/auction. Future multi-auction operations
must acquire auction locks in ascending ID order before any child writes.

Backfill existing Phase 1 bids by ascending ID within each auction. This preserves
legacy sequential history; it cannot reconstruct an unknown historical concurrent
commit order. Stop API writers for migration/application rollout. Migration is
transactional and takes table locks; it is deliberately a maintenance migration,
not a zero-downtime rollout. Rollback removes ordering metadata, retaining bids.

## Alternatives Considered

- Optimistic `lock_version`: possible, but insert and conditional update must roll
  back together and each collision must retry the entire validation with fresh
  state. High contention amplifies work and introduces retry/error policy now.
- Compare-and-swap predicate on current price/state: possible if all authoritative
  predicates and history changes are atomic. It moves more workflow into conditional
  SQL and still requires collision handling; offers no demonstrated benefit here.
- Constraints alone prevent duplicate sequences/invalid rows, not stale minimum
  acceptance or contradictory cross-row state. They remain defense in depth.
- Process-local mutexes cannot coordinate independent Rails instances; Redis would
  add an unnecessary authority/failure boundary. Neither is used.

## Consequences

A waiter sees the predecessor's committed state and either accepts the next valid
bid or gets `bid_too_low` with fresh price/minimum. Other auctions have independent
row locks. A crash/exception before commit rolls back both writes and ordering.
One hot auction serializes writers: lock queues and database connection pressure
are the expected bottleneck. No throughput or latency claim is made.

## Risks

Privileged SQL/validation bypasses can violate cross-row workflow rules. All future
writers must use the same protocol. Long outer transactions prolong lock lifetime.
Unexpected deadlocks/timeouts propagate as database failures; there is no broad
rescue/retry that could obscure a bug or retry an ambiguous commit. Current entry
points avoid opposing lock orders, but unrelated administrative SQL can still
create deadlocks. Reads spanning queries are not snapshot-consistent. App clocks
may differ across hosts, and retries remain non-idempotent.

## Revisit When

Phase 3 introduces private maxima and multiple generated bids per command; preserve
this lock boundary and sequence authority. Phase 4 revisits time/closing. Reconsider
optimistic/CAS strategies only with measured workload evidence and equivalent
invariant tests. Review lock order whenever a command spans multiple aggregates.
