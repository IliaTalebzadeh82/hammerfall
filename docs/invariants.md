# Invariants

## Implemented in Phase 1

Unless explicitly marked SQL, these are guarantees for **sequential calls through
the documented domain entry points**, not for concurrent requests or privileged
validation-bypassing writes.

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| Money is positive, bounded integer cents; fractional input is never silently truncated | MinorUnitsValidator before casting; SQL bigint/range CHECKs | auction_spec.rb, bid_spec.rb, domain_constraints_spec.rb |
| Every accepted bid references one existing auction and bidder | SQL NOT NULL and foreign keys; model validations | bid_spec.rb, domain_constraints_spec.rb |
| New auctions are draft; only documented edges and preconditions are allowed | Auction lifecycle methods and managed-field validation | auction_spec.rb transition matrix, auctions_spec.rb |
| Only active auctions within starts_at <= now < ends_at accept bids | place_bid! | bid_spec.rb, bids_spec.rb |
| First bid meets starting price; subsequent bids meet price + increment | place_bid! | bid_spec.rb, bids_spec.rb |
| Price equals starting price with no bids and the last accepted amount otherwise | create_draft!, edit_draft!, transactional place_bid! | auction_spec.rb, bid_spec.rb, injected-failure rollback example |
| Rejected operations persist neither bid nor price changes | validation before writes and transaction rollback | bid_spec.rb, bids_spec.rb |
| Accepted bids cannot be edited or destroyed through normal model operations | Bid readonly?; no mutation API | bid_spec.rb |
| Auction terms freeze after draft; cancellation cannot discard accepted bids | Auction validations and cancel! | auction_spec.rb |
| At most one stored winner, and none outside closed state | One nullable winner_id; SQL FK and status CHECK | auction_spec.rb, domain_constraints_spec.rb |
| Close chooses the highest accepted bidder, or no winner with no bids | close!; repeated close is a no-op | auction_spec.rb, bids_spec.rb |
| History is stably paginated by server ID and excludes client timestamps | API allowlist, ordered scoped query | bids_spec.rb |

The API returns the persisted winner; it does not promote an active leader into a
winner. The static frontend still has no auction view or independent projection.
Actual files are mapped in [code-map.md](code-map.md). Tests reside under
`apps/api/spec/models`, `spec/requests`, and `spec/integration`.

## Master requirements and remaining work

All 15 original master invariants remain requirements. Their current status is:

1. **Closed auctions cannot accept a new bid:** enforced sequentially; bid/close
   races are not solved.
2. **Same idempotency key cannot create multiple bids:** future Phase 5; there is
   no key handling or retry deduplication now.
3. **Every accepted bid belongs to exactly one auction:** enforced structurally
   by SQL NOT NULL/FK.
4. **At most one authoritative winner:** one winner reference exists; concurrent
   winner/close correctness is still future work.
5. **Deterministic authoritative accepted-bid ordering:** Phase 2. Ordinary IDs
   currently support history, not concurrent commit/acceptance ordering.
6. **Client timestamps cannot determine authoritative ordering:** clients cannot
   set bid timestamps; the authoritative ordering mechanism is still deferred.
7. **Visible winner must agree with PostgreSQL:** API serializes the stored
   winner; real-time/frontend projection consistency is not implemented.
8. **Automatic bid maxima are private:** Phase 3; no maxima exist yet.
9. **Concurrent requests cannot lose updates:** Phase 2; explicitly not guaranteed.
10. **Closure and bid acceptance serialize correctly:** future coordination/time
    work; Phase 1 provides sequential preconditions only.
11. **Committed bids eventually produce domain events:** Phase 9 onward; no outbox
    or event publication exists yet.
12. **Duplicate events do not duplicate downstream effects:** Phase 10 onward.
13. **Read-model inconsistency is detectable:** Phase 12; no read model exists.
14. **Read-model inconsistency is repairable:** Phase 12.
15. **Redis loss cannot invalidate authoritative state:** PostgreSQL is the only
    current store; Redis integration/failure behavior is deferred.

Do not infer concurrency safety from the passing sequential suite. Update this
ledger with enforcement and test references as later phases implement each promise.
