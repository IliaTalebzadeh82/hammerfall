# Consistency model

PostgreSQL stores User, Auction, Bid, current price, and the closed-auction winner.
Phase 1 has no cache or derived external read model. The API reads persisted state;
the frontend still does not display auctions.

A sequential place_bid! call validates active status, time, amount, and minimum,
then persists bid and current price atomically. A savepoint preserves that rollback
scope inside an outer transaction. Rejected calls leave neither a bid nor a price
change. Close selects the highest bidder for its sequential view and stores one
winner reference.

These transactions do not serialize concurrent decisions. Two callers can read
the same current price, both validate, then overwrite price; bid/close races are
also unsolved. Ordinary ID history ordering is not concurrent acceptance order.
Phase 2 must supply database-backed coordination and authoritative ordering.
Phase 4 must establish closing/time authority and race-safe closure.

Reads do not hold a multi-query snapshot. For example, an auction row and its
computed active leader may change between queries under concurrent traffic.
There is no concurrency-consistent projection guarantee yet.
