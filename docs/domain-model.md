# Domain model

Phase 5 adds PostgreSQL-backed HTTP command idempotency around the PostgreSQL-serialized
auction domain. See [ADR-006](adr/006-client-command-idempotency.md) for retries and
[ADR-005](adr/005-auction-deadlines-and-soft-close.md) for deadlines. Read [ADR-004](adr/004-proxy-bidding.md), including its decision
table, for the proxy rules. ADR-003's auction row lock remains authoritative.

## Entities and money

- User: ID and nonblank name (up to 100 characters); names are not credentials.
- Auction: title (nonblank, up to 200), description (up to 10000, default empty),
  status, starting_price, current_price, minimum_increment, starts_at, original_ends_at, ends_at, closed_at,
  current_leader_id, winner_id, timestamps.
- Bid: accepted visible fact with auction_id, bidder_id, amount, sequence,
  created_at and internal origin (manual/automatic). No normal edit/delete path.
- MaximumBid: one current private instruction per auction/bidder, maximum_amount,
  priority_sequence and timestamps. Updates replace the current ceiling/priority;
  no historical private-max audit table exists. No cancellation.

All money is **integer EUR cents**, inclusive range 1..1000000000000. Numeric strings,
floats (including 100.0), booleans and out-of-range input are rejected before Rails
coercion. SQL range checks independently protect storage. There is no conversion,
fractional-cent value, reserve price or dynamic increment table. Fixed positive
auction.minimum_increment applies, with the proxy exceptions below. Price-plus-
increment stays in JavaScript's exact integer range; an offer itself must fit the
bound. Times use UTC, with ends_at strictly greater than starts_at.

## Lifecycle and time

New auctions are draft, price equals starting_price and no leader/winner exists.
Use create_draft! and edit_draft!; terms freeze after draft. No reopen/reschedule.

| Action | Source | Target | Preconditions |
| --- | --- | --- | --- |
| schedule! | draft | scheduled | ends_at has not passed |
| activate! | scheduled | active | starts_at <= DB decision time < ends_at |
| close! | active | closed | DB decision time >= ends_at |
| cancel! | draft, scheduled, active | cancelled | no accepted bids |

Repeating the target state is a no-op. Closed/cancelled are terminal. Existing
lifecycle and draft commands lock/reload the same auction row used by bidding.
Close copies current_leader_id into winner_id, including equal-price priority
winners; without bids both remain null. Already closed and active-not-due close
calls return unchanged. Other states reject close. Activation remains explicit.

Every manual/maximum/close command captures one uncached PostgreSQL
clock_timestamp() **after** lock/reload. There is no injected production time.
Even same-maximum no-ops must be eligible. At decision_time >= ends_at, an active
auction rejects auction_ended with public ends_at. Non-active bidding rejects
invalid_auction_state. Before starts_at it rejects auction_not_open. Request arrival
and transaction start cannot authorize bidding after a wait. Accepted decisions can
commit later while holding the lock; physical commit time is not the eligibility test.

The closer materializes due active auctions independently; rejected bidding does
not lazily close. **Scheduler delay can delay status, never the legal window.**
Close records DB decision time in closed_at, preserves the effective ends_at and
leader, and emits no bid. Duplicate closers preserve winner/closed_at.

### Timing and soft close

starts_at is the earliest eligible time. original_ends_at follows draft edits and
freezes on scheduling. ends_at is the effective deadline. closed_at is actual DB
finalization decision time, possibly later than ends_at, not exact commit time.
All four are public UTC timestamps (closed_at null until closed).

One accepted external manual bid, new max or increased max extends exactly once
when `0 < ends_at - decision_time <= 60`: add **90 seconds to existing ends_at**.
An entire proxy contest generating two rows still adds only 90. Protection-only
increases add 90 even without a visible row. Identical max/rejected commands add
nothing. Later valid commands in their new final minute can extend again without
limit. Auction#persist_bidding_action! saves extension/price/leader in the same
transaction as all private changes and visible rows. Failure rolls everything back.
Generic PATCH cannot edit scheduled/active/closed/cancelled terms or write original
end/closure metadata. There is no force-close, reopen, or post-close max mutation.

## Binding protection and priority

Auction#set_maximum! establishes or increases private protection. New or increased protection
must cover starting price on an empty auction. A challenger to an existing leader
must exceed public current_price (one cent is sufficient for a final partial
increment); a current leader may set protection equal to its price. No instruction
can authorize an automatic offer above its ceiling.

Increases receive a fresh auction-local priority_sequence = MAX(priority_sequence)+1
inside the lock. Repeating the same amount preserves priority and produces no bids.
Decreases raise maximum_bid_cannot_decrease with no private details. Cancellation
is unsupported in the API and rejected by normal model destruction. An exhausted
instruction remains stored; a later competitive increase can compete again. A
nonleader increase at/below current price is rejected without changing protection
or priority. A leader’s increased ceiling must cover its current price. An already-leading bidder setting
or increasing protection never raises its own visible price.

Lowest priority_sequence wins equal ceilings. A raise gets new priority at its new
ceiling, not its original lower commitment's priority. Example: Bob establishes
300 at priority 7; Alice raises 200 to 300 at priority 8; Bob wins. A previously
established proxy also wins against a later manual offer equal to its ceiling.
Priority is independent of public bid sequence, clocks, row IDs or HTTP arrival.

## Proxy resolution and visible history

Auction#place_bid! retains the manual minimum: starting_price without bids,
otherwise current_price + minimum_increment. Manual offers are accepted at exactly
the submitted amount. They may be immediately outbid in the same transaction;
the returned Bid is the caller's accepted offer, not a promise of leadership.

Bidding::ProxyResolver compares the incoming bidder with the authoritative current
leader. All other maxima were already exhausted or lost an equal-ceiling tie at
the last completed command. The incumbent ceiling is its public price or private
maximum, whichever is greater. A manual-only incumbent has ceiling=current_price.

- Without a leader, first maximum produces starting_price, not its ceiling.
- Lower challenger: emit challenger at its ceiling/offer, then incumbent at the
  smaller of its ceiling and challenger + increment.
- Higher challenger: first exhaust the incumbent's proxy ceiling if above public
  price; then emit the manual offer or minimum winning automatic amount.
- Equal ceilings: emit challenger then priority winner at the same amount.
- Partial final increment: clamp an automatic offer to its ceiling, e.g. ceilings
  300/305 with increment 10 resolve at 305, never 310.
- No duplicate existing manual offer or self-counter is generated.

A command emits at most two Bid rows. Visible amounts are **non-decreasing**, not
strictly increasing: equal-price tie resolutions are now valid. Every emitted row
gets the next MAX(sequence)+1 under the auction lock, regardless of origin. Current
price equals the final emitted amount and the last row represents the selected
leader. Protection-only updates change neither price nor leader nor history.
The explicit current_leader_id is selected by ceiling/priority rules; row insertion
order is a consequence, not the tie authority. Winner remains null while active.
An automatic row never exceeds its user's binding maximum. A manual row can exceed
that same user's old maximum because it is a separate explicit authorization.

## Transaction and structural guarantees

Both entry points use transaction(requires_new: true), SELECT FOR UPDATE/reload,
fresh eligibility checks, private-state validation/write if applicable, synchronous
resolution and all visible INSERTs, then final price/leader UPDATE and COMMIT.
All records share the transaction; SQL failure after a partial resolution rolls
back maxima, priorities, bids, price, leader and effective deadline. A nested caller owns final outer
commit and lock lifetime. No network work, queues or callbacks resolve contests.
Maximum association autosave/implicit validation is disabled: the command explicitly
validates and saves each instruction before resolving, within that same transaction.

SQL enforces foreign keys, NOT NULL, bounded money, valid statuses/origins, positive
priority/sequence, UNIQUE(auction_id,bidder_id) for instructions, and separate unique
auction-local sequence/priority indexes. Auction primary key locates the lock;
sequence index supports history; instruction indexes support lookup and priority.
The prior amount index remains for compatibility, but no longer selects the leader.

Normal immutable history has contiguous sequences starting at 1. The contract is
strict monotonicity, not global order or guaranteed gaplessness after privileged
history changes. Rejection/rollback consumes no committed sequence or priority.
ID and created_at remain metadata. Workflow rules are Ruby logic under the lock;
raw SQL/update_all/explicit validation bypasses remain outside that contract.

Migration backfills leader from latest Phase 2 sequence and marks old bids manual.
Stop writers for maintenance rollout. Down migration refuses to discard existing
MaximumBid records; test rollback/reapply uses pre-proxy history. Downgrading a
populated Phase 3 database requires an explicit data-preservation plan.
Phase 4 backfills original end from existing end and legacy closed_at with
GREATEST(updated_at,ends_at), a documented estimate. Its SQL checks require a closure
timestamp iff closed, closure at/after end, ends_at>=original end, and null-safe
winner/leader equality at close. Downgrade refuses detectable new timing history;
export before a live downgrade.

## Privacy and remaining limits

Public presenters omit maximum, priority and origin. Maximum PUT returns only an
acknowledgement. No maximum GET/list/DELETE exists. Parameters, SQL binds and model
inspection filter private fields. Reaching a visible ceiling can inherently reveal
an amount through bidding; it is never labelled as a ceiling or automatic origin.
This provides representation/data privacy, **not authorization-based secrecy**:
unauthenticated supplied bidder IDs permit impersonation/probing. Operators can
read plaintext private database records. Authentication is not redesigned here.

One hot auction serializes work and queues database connections. No fairness,
throughput guarantee or arbitrary multi-query snapshot guarantee is made. Frontend, messaging and later
infrastructure remain deferred.

## Phase 5 logical commands and retained outcomes

The protected HTTP bid/max endpoints require a client Idempotency-Key. Domain
Auction methods remain available for internal callers; they do not infer retry
identity from amounts or bidder IDs. The closer is already idempotent and does not
participate in client key infrastructure.

IdempotencyRecord stores actor_id (User FK), constrained operation, SHA-256 key
digest, canonical request fingerprint, processing/completed status, response status,
public JSONB body, timestamps and expires_at. UNIQUE(actor_id,operation,key_digest)
coordinates all API processes. No raw key, request body or private maximum is stored
here. Raw MaximumBid state remains private as before. Actor scope is not authentication.

IdempotentBidding identifies the actor, then Idempotency::Executor claims/resolves
ownership before Auction lookup, lock, DB deadline time or command evaluation.
Canonical v1 semantic JSON includes operation, integer auction/actor IDs and sorted
amount arguments with JSON scalar types preserved. Formatting/header order is
irrelevant. Same scoped key with different auction/amount yields 409 conflict.
Matching completed records replay their saved HTTP status/body and mark
Idempotency-Replayed: true, even after price/leader changes or closure.

One outer transaction contains ownership, the existing domain savepoint, complete
proxy/extension settlement and response persistence. If snapshot writing fails,
released domain savepoints still roll back with that outer transaction. Owner
rollback removes the processing row; a waiting duplicate can become owner. No
normal committed processing record or recovery lease exists.

Success (200/201), domain/validation rejection (422), and execution-time missing
Auction (404) are terminal snapshots. Key/shape/ID/JSON errors and missing actor
occur before ownership and are not cached. Unexpected exceptions/database failures
roll back rather than caching 500. Rejection details are historical; replay is not
a current auction GET. A new key with the same maximum is a new command and may be
a domain no-op; the old key bypasses the domain entirely.

Default retention is seven days from DB claim transaction start (configurable
1..365 days). Expiry permits pruning; an existing expired record still reserves its
key. Only physical deletion permits reuse. Manual bounded idempotency:prune deletes
completed expired rows with PostgreSQL time and SKIP LOCKED. Automatic cleanup is
future operations work. Downgrade refuses to drop retained outcomes. Retention,
response version compatibility and authentication identity changes require review.
