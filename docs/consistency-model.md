# Consistency model

PostgreSQL stores User, Auction, Bid, current price, sequence, private maxima/priority, explicit leader and closed-auction
winner. There is no external projection/cache; the frontend has no auction view.

At READ COMMITTED, place_bid! locks and reloads its auction before validating
status, time, amount and minimum. It assigns MAX(sequence)+1 and persists bid and
price atomically. Existing lifecycle and draft commands share that lock. A waiter
sees committed predecessor state; rollback leaves neither bid nor price change.
Nested calls use savepoints, with final durability and lock lifetime owned by the
outermost transaction. See ADR-003. The resolved price equals the latest sequence's
amount; equal amounts can exist and explicit priority selects the stored leader. Same-auction writers serialize across sessions;
other auction rows are independent. No FIFO, fairness or global order is promised.

Application clocks and explicit lifecycle actions remain; synchronized clock
policy, closing workers and soft-close are Phase 4. Idempotent retries are Phase 5.
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
