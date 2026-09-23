# Domain model

Phase 1 implements correct **sequential operations** using PostgreSQL. Concurrent
bid/lifecycle serialization is not implemented; see [ADR-002](adr/002-core-auction-state.md).

## Entities and representation

| Entity | Stored fields | Meaning |
| --- | --- | --- |
| User | id, name, created_at, updated_at | Minimal bidder identity; names need not be unique and are not credentials |
| Auction | id, title, description, status, starting_price, current_price, minimum_increment, starts_at, ends_at, winner_id, timestamps | Authoritative persisted auction state for the current sequential implementation |
| Bid | id, auction_id, bidder_id, amount, created_at | An accepted, immutable manual bid; rejected attempts do not create rows |

All monetary fields are **integer EUR cents**, not euros or floating point. For
example, `10500` means EUR 105.00. Each value must be an integer from 1 through
1,000,000,000,000 inclusive. The API rejects decimal numbers (including `100.0`),
numeric strings, booleans, and out-of-range values instead of coercing them.
`MinorUnitsValidator` inspects values before ActiveRecord's integer casting.
PostgreSQL bigint and CHECK constraints protect stored ranges. The bound also
keeps price-plus-increment exact in JavaScript JSON consumers. If the next minimum
exceeds the supported amount bound, no further valid bid is possible.

EUR is currently the sole supported currency, exposed by presenters as a constant.
There is no conversion, configurable currency, payment, or fractional-cent feature.
Review this assumption before expanding the product. PostgreSQL numeric would also
be valid, but adds scale/rounding decisions without a present requirement.

Title is nonblank and at most 200 characters; user name is nonblank and at most
100. Description defaults to an empty string and is limited to 10,000 characters
by the application. Both timestamps are required, with ends_at strictly after
starts_at. All times are stored/serialized in UTC through Rails.

## Explicit lifecycle

New auctions always start as draft. Use `Auction.create_draft!` to initialize
current price. `edit_draft!` edits draft terms and adjusts the initial current price.
All terms freeze after scheduling, including title/description. There is no
reschedule/reopen/delete HTTP operation.

| Operation | Allowed source | Target | Preconditions |
| --- | --- | --- | --- |
| schedule! | draft | scheduled | ends_at is still in the future; starts_at may already have arrived |
| activate! | scheduled | active | starts_at <= application time < ends_at |
| close! | active | closed | application time >= ends_at |
| cancel! | draft, scheduled, active | cancelled | no accepted bids |

Repeating an operation while already at its target status is a successful no-op,
even if its original time precondition no longer holds. It does not recompute the
winner. Every other transition is rejected. Closed and cancelled are terminal.
A direct ordinary `auction.update!(status: "closed")` fails validation; callers
must use the lifecycle methods. Validation guards contain no state-changing
callbacks. Their internal validation contexts are conventions, not a security
boundary against deliberate validation bypasses or SQL.

## Status and time

**Stored status is lifecycle authority.** Timestamps define a half-open bidding
window: starts_at is inclusive; ends_at is exclusive. Both status active and the
time window must permit a bid. Time passing never changes status by itself. Thus,
an ended auction can remain active until explicitly closed, but accepts no more
bids; a scheduled auction does not activate itself. Activation after the window
ends is rejected; it may still be cancelled if it has no bids.

Phase 1 samples `Time.current` in Ruby; no scheduler, database-clock protocol,
distributed clock guarantee, or race-safe closing exists. Trusted internal `at:`
arguments support deterministic tests and demo history. HTTP clients cannot supply
authoritative time. Phase 4 must revisit clock authority and closing races.

## Bidding and current price

`Auction#place_bid!` is the one normal write entry point. It reloads the auction,
checks active status/time, validates an existing bidder and exact positive amount,
then applies:

```text
no accepted bids: minimum = starting_price
otherwise:       minimum = current_price + minimum_increment
```

A bid may exceed the minimum, including on the first bid. The same bidder may bid
again. In a transaction, insert the bid and persist current_price = bid.amount.
If either write fails, both roll back. A nested call uses a savepoint so this also
holds if an outer caller catches the failure and commits its own work. Before any accepted bid, current_price =
starting_price. Rejected bids change neither table.

This duplicated price simplifies reads and provides a place for future visible
pricing rules. It must not be updated independently. Normal direct Bid.create!
and current-price mutations fail validation; accepted bids reject normal update!
and destroy! calls. Foreign keys restrict deletion of referenced users/auctions.
Privileged update_all, delete_all, raw SQL, and explicit validation bypasses are
outside these workflow guarantees.

Reloading avoids stale Ruby objects across sequential calls. **It is not a lock**.
Concurrent calls can still validate against the same old price and overwrite one
another. A transaction protects atomic writes, not the complete read/check/write
sequence from concurrent interference. Phase 2 owns that work.

## Leader, winner, and history

The highest accepted bid determines the current leader. The API exposes
current_leader_id only while active; it is not a formal winner. On explicit close,
winner_id is assigned to the highest bidder, or remains null when no bids exist.
An auction has one nullable winner reference, and the database forbids a non-null
winner outside closed status. Cancelled auctions have no bids or winner under
normal operations. No refund/retraction policy is invented.

History is ascending server-generated bid ID, with keyset pagination. IDs are
ordinary insertion identifiers: they can have gaps and **are not commit order or
an authoritative concurrent acceptance sequence**. created_at is insertion
metadata. No client timestamp is accepted. The leading-bid query uses amount
descending then ID ascending for deterministic selection; equal accepted amounts
cannot occur in valid sequential bidding, so this is not an automatic-bidding tie
policy.

## Database versus application

PostgreSQL enforces NOT NULL, foreign keys, positive bounded amounts, allowed status,
nonblank names/titles, end-after-start, price-at-least-start, and winner-only-when-
closed. Indexes cover bid history `(auction_id, id)`, highest bid
`(auction_id, amount DESC, id)`, and bidder/winner references. Primary keys supply
identity uniqueness; display names and auction titles deliberately are not unique.

Ruby enforces legal transitions, time eligibility, minimum bid, frozen terms,
immutable accepted history, winner selection, and atomic price/history updates.
Cross-row workflow rules are not duplicated in triggers. See the SQL-bypass tests
in `spec/integration/domain_constraints_spec.rb` for the exact database guarantees.

## Deferred concepts

AutomaticBid (Phase 3), IdempotencyRecord (Phase 5), OutboxEvent (Phase 9), concurrency
ordering (Phase 2), and race-safe closure (Phase 4) are not implemented. There is no
authentication; client-supplied bidder_id is a local/demo actor selector only.
