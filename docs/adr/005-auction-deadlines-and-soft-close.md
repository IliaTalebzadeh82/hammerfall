# ADR-005: Auction deadline, closing and soft-close semantics

Status: Accepted — Phase 4, 2026-09-24

## Context

Five Rails instances can disagree about wall time. A scheduler can be late, and a
request arriving before expiry can wait on another transaction until after expiry.
Row locking alone does not fix a time value captured before that wait. Phase 3's
private binding maxima, priority, settled history and explicit leader must survive
this change unchanged.

## Time authority

Every bidding/closing command begins a transaction/savepoint, reloads the auction
with SELECT FOR UPDATE, then captures **one** PostgreSQL `clock_timestamp()` through
AuctionClock.now. The query explicitly bypasses Rails query caching and borrows the
current connection without permanently checking it out. Schedule and activate also
use this clock. There is no production `at:` override.

PostgreSQL NOW()/CURRENT_TIMESTAMP/transaction_timestamp() describe transaction
start, even after a long lock wait. They are unsuitable here. Statement time can
also precede waiting if evaluated as part of the locking statement. A separate
clock query after the lock returns is straightforward. Database wall-clock itself
can jump if the host clock is adjusted; this is one authority, not a monotonic or
multi-region time service.

Eligibility requires active status and starts_at <= decision_time < ends_at.
At equality or later, an active auction rejects with auction_ended and public
ends_at. Other inactive states retain invalid_auction_state. Arrival, controller
and transaction-start timestamps cannot authorize bids. A valid decision may
commit later: legality is measured at the locked decision, not at physical commit.
An outer transaction still owns final commit and lock release.

## Closing and winner

Auction#close! is the single finalizer used by the HTTP close endpoint and closer.
It locks/reloads, samples time, returns unchanged if already closed or active but
not due, and otherwise sets closed status, winner_id=current_leader_id and
closed_at=decision_time in one transaction. Non-active, non-closed states reject
invalid_state_transition. A stale closer treats cancellation as a benign skip.
There is no force-close or reopen. Closing emits no Bid and never inspects maxima
to choose a winner. The settled leader, including durable equal-ceiling priority,
is authoritative. No leader means no winner. Repeated closure never changes
closed_at/winner/updated_at. Private maximum records remain frozen history.

We deliberately **reject without lazy finalization** on the bidding path. This
keeps every rejected bid transaction free of committed mutations and avoids
raising a domain exception that accidentally rolls back intended lazy closure.
The independent closer or explicit close call eventually materializes lifecycle.
Scheduler delay may delay visible status, never the legal bidding deadline.

## Soft close and logical contest

For each accepted external manual bid, new maximum or actual maximum increase:

```text
0 < ends_at - decision_time <= 60 seconds => ends_at = ends_at + 90 seconds
```

Exactly 60.000 is inside; 60.001 is outside. Add to the existing deadline; at 37
seconds remaining the result has 127 seconds remaining. There is no extension cap.
A later command in its new final minute may extend again. A maximum increase can
extend without changing price or emitting a row. Identical maximum is a no-op;
rejected commands do not extend. Internal proxy rows do not each extend.

Auction#persist_bidding_action! performs the calculation once after resolution,
then saves price, leader and effective deadline. Private max/priority and every
visible Bid share the entry transaction. A failure in the final UPDATE rolls all
of them back. ProxyResolver only assigns price/leader in memory and inserts rows;
it does not independently persist the auction or control time.

## Timestamp fields and rollout

- starts_at: earliest bidding eligibility; activation remains explicit.
- original_ends_at: deadline set by draft creation/editing, frozen on scheduling.
- ends_at: current effective deadline, changed after draft only by soft close.
- closed_at: DB decision time of finalization, not physical commit time. A delayed
  closer legitimately records a value later than ends_at.

All API timestamps are UTC ISO 8601. Both leader and winner remain publicly visible
after closure; neither is a private ceiling. Ordinary PATCH still edits only draft
terms; timing metadata cannot be supplied.

Maintenance migration locks auctions, backfills original_ends_at=old ends_at and
legacy closed_at=GREATEST(updated_at,ends_at). The latter is an **estimate** because
Phase 3 did not record a DB closure decision. It does not retroactively prove clock
accuracy. SQL enforces original deadline non-null, ends_at>=original_ends_at,
and, after the Phase 12.5 hardening migration, original_ends_at>starts_at;
closed_at present iff closed, closed_at>=ends_at and null-safe winner/leader equality
when closed. Foreign keys remain. Stop old writers and closer during rollout.
Rollback/reapply preserves pre-Phase-4 records; downgrade refuses detectable live
extensions/closure timestamps. Export and plan preservation before any live downgrade;
removing these columns cannot preserve the new timing history automatically.

## Scheduler and multiple closers

bin/auction_closer boots the same Rails application, not another microservice.
AuctionCloser discovers a bounded batch of active IDs ending before a sampled DB
cutoff, ordered by ends_at,id. A partial active (ends_at,id) index supports the
predicate/order; a constant cutoff permits index range access. This is only a hint.
Each candidate calls close! and rechecks fresh status/end/time under lock. Several
processes may discover identical IDs: one transition wins and the rest see closed.
No leader election or distributed lock is needed.

Default interval is one second and batch size 100; environment settings bound work.
--once supports operational sweeps and exits unsuccessfully if a candidate failed
transiently, so a partial sweep is not reported as complete. SIGINT/SIGTERM stop after the in-flight command,
with interruptible short poll sleeps. The executable defaults PostgreSQL lock and
statement timeouts to 5s/10s through PGOPTIONS. Known transient DB failures are logged
and retried by later discovery; unknown per-auction errors log ID/class and propagate
so operators see failure. Logs omit SQL and private values. Startup/shutdown are logged.
Compose restarts a failed process. There is no scheduler health SLA or telemetry stack.

## Alternatives considered

- Rails process clocks: can disagree across instances.
- Transaction-start DB time: becomes stale while waiting for serialization.
- Request arrival time: would legalize a request that wins its lock after expiry.
- Singleton scheduler: does not protect against stale candidates or late requests;
  unnecessarily makes correctness depend on one process.
- Request-only lazy closure: auctions without traffic never materialize closed;
  rejection/commit handling becomes more subtle. No lazy mutation is used here.
- Sidekiq: adds Redis/queue operations before this workload justifies them; Phase 8.
- Reset ends_at to now+90: violates the required fixed addition to the prior end.
- Extend per generated proxy Bid: duration depends on internal settlement details.
- Distributed lock/leader election: a second authority adds failure modes while the
  existing PostgreSQL row already serializes all relevant commands.

## Consequences and risks

Stronger time semantics add a database round trip/dependency. The hot auction lock
remains the bottleneck and long outer transactions hold it longer. Multiple closers
are safe but may do duplicate discovery and wait behind the same hot candidate;
this is not a throughput optimization. Status can lag deadline, while legal
acceptance cannot. Database outages reject/delay operations rather than falling
back to a local clock. No FIFO, exactly timed status transition, capacity or fairness
claim is made. Supplied actor IDs remain unauthenticated, retries are not generally
idempotent, and privileged SQL can bypass workflow rules.

## Revisit when

Multi-region PostgreSQL, measured closing throughput bottlenecks, event-driven
scheduling, tighter materialization SLA or changed clock discipline justify it.
Phase 5 must ensure replayed accepted commands do not rerun proxy settlement or add
another extension, even if the response was lost or the auction has since closed.

Phase 5 follow-up: [ADR-006](006-client-command-idempotency.md) now provides that
retry protection for the two public bidding commands. The risks above describe the
Phase 4 decision; internal domain calls still require their own command identity.
