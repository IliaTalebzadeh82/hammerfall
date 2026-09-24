# Domain model

Phase 3 adds binding private MaximumBid instructions to the PostgreSQL-serialized
auction domain. Read [ADR-004](adr/004-proxy-bidding.md), including its decision
table, for the proxy rules. ADR-003's auction row lock remains authoritative.

## Entities and money

- User: ID and nonblank name (up to 100 characters); names are not credentials.
- Auction: title (nonblank, up to 200), description (up to 10000, default empty),
  status, starting_price, current_price, minimum_increment, starts_at, ends_at,
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
| activate! | scheduled | active | starts_at <= application time < ends_at |
| close! | active | closed | application time >= ends_at |
| cancel! | draft, scheduled, active | cancelled | no accepted bids |

Repeating the target state is a no-op. Closed/cancelled are terminal. Existing
lifecycle and draft commands lock/reload the same auction row used by bidding.
Close copies current_leader_id into winner_id, including equal-price priority
winners; without bids both remain null. No automatic activation/closing scheduler.

Manual and maximum commands recheck active status and the half-open time window
inside the lock, sampling Time.current after waiting. Even same-maximum no-ops
recheck eligibility. Trusted internal at: values support tests/seeds; HTTP cannot
set authoritative time. Application clocks, explicit closure and unchanged ends_at
remain Phase 3 limitations. There is no soft close or distributed time redesign.

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
back maxima, priorities, bids, price and leader. A nested caller owns final outer
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

## Privacy and remaining limits

Public presenters omit maximum, priority and origin. Maximum PUT returns only an
acknowledgement. No maximum GET/list/DELETE exists. Parameters, SQL binds and model
inspection filter private fields. Reaching a visible ceiling can inherently reveal
an amount through bidding; it is never labelled as a ceiling or automatic origin.
This provides representation/data privacy, **not authorization-based secrecy**:
unauthenticated supplied bidder IDs permit impersonation/probing. Operators can
read plaintext private database records. Authentication is not redesigned here.

One hot auction serializes work and queues database connections. No fairness,
throughput guarantee or arbitrary multi-query snapshot guarantee is made. Distributed
closing/soft-close (Phase 4), idempotency (Phase 5), frontend, messaging and later
infrastructure remain deferred.
