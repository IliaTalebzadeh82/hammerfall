# Deadlines, soft close and finalization

## Authority and main flow

After obtaining the auction row lock, a bidding or closing command samples uncached PostgreSQL `clock_timestamp()`. Eligibility is `active` and `starts_at <= decision_time < ends_at`; transaction-start, app, browser and scheduler clocks cannot authorize a bid. All stored API times use UTC. A valid decision can commit after the deadline while still holding the lock.

The explicit `Auction#close!` finalizer and independent Rails closer role share this protocol. Closer discovery of bounded due IDs is only a hint: it locks and rechecks each candidate. Duplicate/stale workers are safe; early or repeated close is a no-op and must not change winner or `closed_at`. The final winner is the already settled leader, or null; closing creates no bid. Delayed polling may leave visible status active after deadline, but cannot admit late bids. A rejected bid does not lazily close.

## Soft-close rule

For each accepted external manual bid or new/raised maximum, one logical contest extends `ends_at` by 90 seconds when `0 < ends_at - decision_time <= 60 seconds`. Repeated qualifying contests can extend again; a protection-only raise can extend without a visible bid. A generated proxy row does not cause its own extension; rejected and identical commands do not extend. Deadline, price, leader, private state and visible rows share the transaction. `original_ends_at` remains the original term, strictly after `starts_at` and no later than `ends_at`; model, SQL and public-snapshot validation now enforce this relation. `closed_at` is the DB decision time, not commit time.

## Failure and change boundaries

PostgreSQL outage makes eligibility unavailable; do not fall back to app time. Clock adjustments and late scheduling are operational concerns, not reasons to weaken authority. A client countdown is presentation and must refresh at zero. [ADR-005](../adr/005-auction-deadlines-and-soft-close.md) is canonical for exact boundaries, migration/downgrade limits, closer configuration and alternatives. See [AuctionClock](../../apps/api/app/models/auction_clock.rb), [AuctionDeadline](../../apps/api/app/models/auction_deadline.rb) and [AuctionCloser](../../apps/api/app/services/auction_closer.rb).
