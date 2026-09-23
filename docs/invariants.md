# Invariants

All items below are requirements from the master specification. **None is yet
enforced by domain code**: Phase 0 contains no auction domain. Later phases must
add enforcement and test references here without weakening these requirements.

1. A closed auction cannot accept a new bid.
2. A bid request with the same idempotency key cannot create multiple bids.
3. Every accepted bid belongs to exactly one auction.
4. An auction can have at most one authoritative winner.
5. Accepted bids have a deterministic authoritative ordering.
6. Client timestamps cannot determine authoritative ordering.
7. The visible auction state must never claim a winner that contradicts PostgreSQL authoritative state.
8. Automatic bid maximum values are private.
9. Two concurrent requests must not result in lost updates.
10. Auction closure and bid acceptance must be serialized correctly.
11. A committed accepted bid must eventually produce its corresponding domain event.
12. Duplicate event delivery must not create duplicate downstream effects.
13. Read-model inconsistency must be detectable.
14. Read-model inconsistency must be repairable.
15. Redis loss must not invalidate authoritative auction state.

Phase 1 establishes model constraints and lifecycle semantics. Later phases add
the transactional, ordering, privacy, retry, delivery, and recovery guarantees.
A passing foundation health test is not evidence for any auction invariant.
