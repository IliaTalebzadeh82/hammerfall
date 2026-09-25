# Consistency model

PostgreSQL stores User, Auction, Bid, current price, sequence, private maxima/priority, explicit leader and closed-auction
winner. There is no external projection/cache; the frontend renders request/response public state that can become stale between refreshes.

At READ COMMITTED, place_bid! locks and reloads its auction before validating
status, time, amount and minimum. It assigns MAX(sequence)+1 and persists bid and
price atomically. Existing lifecycle and draft commands share that lock. A waiter
sees committed predecessor state; rollback leaves neither bid nor price change.
Nested calls use savepoints, with final durability and lock lifetime owned by the
outermost transaction. See ADR-003. The resolved price equals the latest sequence's
amount; equal amounts can exist and explicit priority selects the stored leader. Same-auction writers serialize across sessions;
other auction rows are independent. No FIFO, fairness or global order is promised.

Deadline decisions use one uncached PostgreSQL clock_timestamp() after lock acquisition.
Bids/maxima and each qualifying +90 extension commit atomically. The independent
closer locks/reloads/rechecks; duplicate close preserves winner and closed_at.
Delayed active status never permits post-deadline decisions. Accepted decisions may
commit later while holding the lock; closed_at records decision rather than commit
time. Rejected commands do not lazily close. Protected HTTP bid/max retries use retained PostgreSQL idempotency outcomes.
Unexpected database failures are not broadly retried or masked as domain errors.

Reads do not hold a cross-query snapshot. Auction state and separately fetched bid
history may reflect different commits during traffic. Price and stored leader in
one auction response now come from the same row; arbitrary multi-query views are
not promised snapshot consistency.


Phase 3 maximum changes and synchronous counters share that same auction transaction.
No intermediate challenger state is committed. Exceptions roll back private priority,
maxima and all generated rows with price/leader. Protection-only updates may commit
without any visible bid. The HTTP manual response still identifies its accepted row,
which can already be outbid. Public auction price/leader now come from one row;
arbitrary cross-endpoint reads still need not observe the same commit.

Phase 5 stores scoped client-key digests, semantic fingerprints and public terminal
responses in the same PostgreSQL transaction as bidding. Key ownership precedes
Auction locking; replay bypasses domain state/time evaluation. Internal Auction
calls remain unwrapped. Records default to seven-day prune eligibility; expired rows
reserve their keys until physical deletion. This is bounded retry protection, not
permanent deduplication or authentication. Retained outcomes add storage and lock
lifetime; cleanup and API snapshot compatibility need operational ownership. No
performance improvement is claimed without measurement. See ADR-006.

Phase 6 never optimistically changes price/leader or closes at local zero. It
separates historical command outcomes (including replay) from fresh auction/history
GETs, rejects late superseded read completions, and retains immutable pending keys
for explicit retries. This does not make multi-query reads snapshot-consistent or
provide realtime delivery. See ADR-007 and frontend.md.
