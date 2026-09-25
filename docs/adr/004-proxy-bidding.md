# ADR-004: Binding private maxima and synchronous proxy resolution

Status: Accepted — Phase 3, 2026-09-24

Time, closing and extension details below describe the original phase decision.
[ADR-005](005-auction-deadlines-and-soft-close.md) supersedes those details in Phase 4.

## Context

A maximum is permission to spend up to a ceiling, not a visible offer of that
ceiling. The Phase 2 lock/order/atomicity guarantees must cover the entire contest.
Equal-price proxy ties need explicit priority and a stored leader, not ID order.

## Decision

Use one current MaximumBid per auction/bidder. Increases are binding; lowering and
cancellation are forbidden. Same amount is a no-op after lifecycle/time validation.
New or increased instructions must cover starting_price without bids; otherwise a challenger
must exceed current_price (partial increment allowed), or a leader may cover its
current price. Noncompetitive increases are rejected without allocating priority.
Otherwise a dormant commitment at a manual leader’s existing price could later
contradict equal-ceiling priority when that leader adds protection. No historical
maximum audit table is introduced.

Every new/increased commitment receives MAX(priority_sequence)+1 under the auction
lock, independently of visible Bid.sequence. Same amount preserves priority. The
lowest priority wins equal maxima, including an incumbent proxy against a later
manual offer at its ceiling. A raise receives new priority at the new amount.

Bidding::ProxyResolver has one pairwise resolution rule. After every completed
command, all other stored maxima are exhausted at/below the public price or lose
an equal-ceiling priority tie. Thus only the incoming bidder and current leader
can alter the result. The incumbent ceiling is max(public price, its stored max).
A manual challenger authorizes exactly its submitted amount; a maximum challenger
authorizes its ceiling. No increment-by-increment loop over dormant bidders is needed.

The loser visibly reaches its authorized ceiling if above the current price;
then the winner offers the smaller of its maximum and loser ceiling + increment.
A manual winner offers exactly the submitted amount. Existing manual commitments
are not duplicated. Equal-ceiling challengers may produce two equal-price rows,
loser then priority winner. A leader setting/increasing protection emits no row.
Manual self-raises retain Phase 2 behavior. No proxy exceeds its declared ceiling.

### Decision table (amounts in example units, starting 100, increment 10)

A is incumbent, B incoming; A's proxy has earlier priority. P is public price.

| Incoming | Incumbent | Incoming ceiling | Incumbent ceiling | Tie rule | Visible rows generated | New price | Leader |
| --- | --- | --- | --- | --- | --- | --- | --- |
| manual | manual at 100 | 200 | 100 | none | B 200 | 200 | B |
| manual | proxy at 100 | 200 | 300 | none | B 200, A 210 | 210 | A |
| manual | proxy at 100 | 350 | 300 | none | A 300, B 350 | 350 | B |
| manual | proxy at 100 | 300 | 300 | earlier proxy | B 300, A 300 | 300 | A |
| maximum | no leader | 300 | none | none | B 100 | 100 | B |
| maximum | manual at 300 | 500 | 300 | none | B 310 | 310 | B |
| maximum | proxy at 100 | 240 | 300 | none | B 240, A 250 | 250 | A |
| maximum | proxy at 100 | 400 | 300 | none | A 300, B 310 | 310 | B |
| maximum | proxy at 100 | 300 | 300 | lower priority sequence | B 300, A 300 | 300 | A |
| maximum | proxy at 100 | 305 | 300 | none | A 300, B 305 | 305 | B |
| maximum | manual at 220, increment 20 | 230 | 220 | none | B 230 | 230 | B |
| own maximum increase | own leader at P | higher ceiling | own old ceiling | new priority | none | P | unchanged |
| nonleader max increase | any at P | still <= P | >= P | rejected, no priority change | none | P | unchanged |

## Visible history and leader

Bid origin is internally manual/automatic, never a public field. Sequences strictly
increase; visible amounts are non-decreasing. Equal amounts are permitted only as
part of priority resolution. Current price equals the final emitted amount, or
stays unchanged for protection-only updates. Auction.current_leader_id is selected
by ceiling/priority rules and stored atomically, not inferred from equal row IDs.
The final emitted row represents that leader. winner_id remains separate and is
copied from the leader only by existing explicit close under the same lock.

## Transaction model

Auction commands BEGIN/savepoint, lock/reload auction, sample time and validate,
read/update private instruction, resolve contest, assign visible sequences, INSERT
all bids, UPDATE price/leader, COMMIT. No asynchronous response, external call or
process-local synchronization. Failure rolls back max, priority, every bid and
price/leader together. Nested callers own the outer commit/lock lifetime.

## Privacy

No public maximum read/list/delete endpoint. PUT acknowledges auction/bidder only,
not even the caller's amount or priority; identity is still unauthenticated.
Presenters allowlist public fields and omit maximum/priority/origin. Errors contain
only public state and generic validation messages. Rails filters maximum_amount
parameters, SQL binds and model inspection. Public bidding may necessarily reach
a ceiling, but responses do not label it as a maximum or disclose unused protection.
This is representation/data privacy, not authorization-based secrecy: impersonation
and probing remain possible without authentication, which is outside Phase 3.

## Alternatives Considered

- Expose maximum as Bid: overcharges and leaks unused protection.
- Store maxima only and synthesize price without history: loses auditable visible
  competition and breaks the established accepted-bid sequence contract.
- Asynchronous counters: publishes an intermediate false leader and separates
  price/max updates into transactions that can fail independently.
- Allow reductions/cancellation: undermines binding commitments and needs reversal
  rules explicitly excluded from this phase.
- Derive ties from last row/timestamps: conflates presentation with durable priority.

## Consequences

Each contest generates at most two visible rows; a protection-only update generates
none. More reads/writes occur under the hot auction row lock than Phase 2. No
measured lock-duration or throughput claim is made without explicit evidence.

## Risks

All writers must preserve settled-state assumptions and the lock order: auction,
then max/bids, then final auction write. SQL bypasses are outside workflow guarantees.
Private records are plaintext database state accessible to operators. HTTP actor IDs
are not credentials. Request replay is not generally idempotent, despite same-max
no-ops. App clocks and manual closure remain; no soft close is introduced.

## Revisit When

Phase 4 defines closing/time/extension behavior. Revisit pricing/priority policy
before dynamic increments, reserve prices or bidder retractions. Use measured load
evidence before changing the concurrency strategy or adding more indexes.
