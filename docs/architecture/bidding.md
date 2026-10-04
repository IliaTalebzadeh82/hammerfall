# Manual and private maximum bidding

## Responsibility

One locked auction command resolves a manual offer or binding private maximum into settled public price, leader and zero to two accepted Bid rows. It does not publish an intermediate challenger as final state.

## Rules and invariants

- An initial manual bid must meet the starting price; later manual bids must satisfy the current minimum. Validate on fresh state after locking, and return a deliberate stale/too-low rejection with public current price and minimum.
- Phase 21 adds a per-auction `fixed` (historical default) or `stepped` increment policy. The stepped schedule is defined in [ADR-018](../adr/018-stepped-bid-increments.md). The current public price chooses the manual band; a proxy counter uses the loser's newly visible price. The public `minimum_increment` field is the effective amount at the current price. Private ceiling and equal-priority exceptions still apply.
- A draft may configure a private reserve at or above starting price. Manual bids below it remain valid. A maximum below reserve becomes visible at its ceiling; an authorized higher maximum advances toward reserve without exceeding its ceiling. Competition can require a higher loser-based counter. Public state contains `none`, `not_met` or `met`, never the private amount; see [ADR-019](../adr/019-hidden-reserve-policy.md).
- A maximum is permission up to a private ceiling, not a public bid of that entire amount. One MaximumBid per auction/bidder may be raised but not lowered/cancelled under the adopted policy. Same-value repeat is a no-op after eligibility checks; a noncompetitive increase is rejected. Each actual raise receives new private priority.
- The incumbent and challenger are resolved synchronously. An earlier priority wins equal-ceiling ties, including a prior proxy versus a manual challenge at the ceiling. Public history may contain equal amounts for a tie; amount/row ID alone cannot determine leader. No generated proxy bid may exceed its ceiling. A complete contest may add two ordered visible rows, or none for a protection-only change.
- Maximum/priority/origin are private. Public serializers, errors, Cable payloads and logs must not disclose unused protection. This is representation privacy only while actor IDs are unauthenticated; database operators can see plaintext private records.
- All private instruction changes, public bids, price, leader and any soft-close extension commit or roll back together under the auction lock. Do not perform an asynchronous counter or a network call inside the transaction.

## Evidence and tradeoff

[ADR-004](../adr/004-proxy-bidding.md) is canonical for the decision table, settled-state proof and exact tie behavior. [ADR-003](../adr/003-auction-concurrency-control.md) covers ordering. The implementation is [Auction](../../apps/api/app/models/auction.rb) and [ProxyResolver](../../apps/api/app/models/bidding/proxy_resolver.rb). Real PostgreSQL concurrent specs, model specs and live HTTP smoke tests are identified in [invariants](../invariants.md). The extra private reads and up to two inserts lengthen the hot-row critical section; no capacity claim exists.
