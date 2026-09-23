# Domain model

No business models, domain tables, or domain migrations exist in Phase 0.
This is a requirements index, not an implemented schema.

| Future concept | Responsibility | Earliest phase |
| --- | --- | --- |
| User | Minimal bidder identity | 1 |
| Auction | Prices, timing, lifecycle, authoritative winner | 1 |
| Bid | Bidder, auction, amount, authoritative order | 1; serialization in 2 |
| AutomaticBid | Private maximum and automatic bidding policy | 3 |
| IdempotencyRecord | Retry deduplication and request fingerprint | 5 |
| OutboxEvent | Durable events committed with domain state | 9 |

Auction statuses required by the specification are draft, scheduled, active,
closed, and cancelled. Allowed transitions and database constraints must be
specified and tested in Phase 1. Monetary representation, authentication,
ordering, time authority, tie rules, and retention are not decided by this scaffold.
Use UTC internally. Client clocks must not determine authoritative ordering.
