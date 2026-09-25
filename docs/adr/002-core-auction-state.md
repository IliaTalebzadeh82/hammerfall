# ADR-002: Persist explicit auction state and integer minor-unit prices

Status: Accepted — Phase 1, 2026-09-24

Time, closing and extension details below describe the original phase decision.
[ADR-005](005-auction-deadlines-and-soft-close.md) supersedes those details in Phase 4.

## Context

Sequential bidding needs an unambiguous money representation, lifecycle, current
price, and winner before bid serialization is introduced. Rails type coercion must
not silently truncate fractional bid amounts. Future automatic bidding needs a
visible price independent of private maxima.

## Decision

All money is integer EUR cents in PostgreSQL bigint columns, bounded to
1,000,000,000,000 cents per value. This keeps arithmetic exact and JSON numbers
within JavaScript's exact integer range, including price-plus-increment. There is
one currency, EUR; no exchange rates or multi-currency feature.

Store current_price on Auction. Before the first bid it equals starting_price;
after an accepted bid it equals that bid's amount. Insert the bid and update price
in one database transaction (a savepoint when nested). This provides atomicity,
not concurrent serialization. The savepoint preserves rollback even when an outer
caller handles an exception without aborting its whole transaction.

Use explicit model operations for creation, draft editing, bids, and lifecycle
actions. Validation guards reject normal saves that bypass managed state changes.
Do not hide writes in callbacks. Persist only accepted, immutable bids.

Status records lifecycle. A bid additionally requires starts_at <= application time
< ends_at. Time alone does not transition status. Manually activate within that
window and close at/after its end. Close records the highest bidder as winner;
without bids, winner remains null. An active leader is not a winner. Cancellation
is permitted only before an accepted bid. Repeating an action at its target state
is a no-op. Closed and cancelled states are terminal.

## Alternatives Considered

- Floating point: unsuitable for exact monetary comparisons.
- PostgreSQL numeric: valid, but introduces scale and rounding rules without a
  current need for fractional minor units.
- Derive current price on every read: reduces duplicated state, but does not match
  the intended authoritative auction aggregate as well and complicates future
  visible-price rules. An explicit transaction and rollback tests protect the
  stored value for sequential operations.
- State machine gem or mutation callbacks: add indirection to five simple states.

## Consequences

Current price is deliberately duplicated and must be updated with bid history.
Domain entry points and tests make that relationship visible. SQL constraints
protect row integrity and references; workflow rules remain in Ruby. Bids have
ordinary server-issued IDs for stable history pagination, not an authoritative
concurrent acceptance sequence.

## Risks

Concurrent bids or lifecycle calls can still race and corrupt the intended
cross-row relationship. Application clocks and manual lifecycle actions are not
race-safe closure. Validation contexts are internal conventions, not protection
against privileged SQL/update_columns/validation bypasses. User IDs supplied by
clients are demo identity, not authentication or authorization.

## Revisit When

Phase 2 must serialize bidding and establish authoritative ordering. Phase 3 adds
automatic bidding; Phase 4 establishes race-safe closing and authoritative time.
Review currency, amount bounds, cancellation policy, and freeze-on-scheduling rules
before supporting real auctions. Changes require updated docs and tests.
