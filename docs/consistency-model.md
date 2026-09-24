# Consistency model

PostgreSQL stores User, Auction, Bid, current price, sequence and closed-auction
winner. There is no external projection/cache; the frontend has no auction view.

At READ COMMITTED, place_bid! locks and reloads its auction before validating
status, time, amount and minimum. It assigns MAX(sequence)+1 and persists bid and
price atomically. Existing lifecycle and draft commands share that lock. A waiter
sees committed predecessor state; rollback leaves neither bid nor price change.
Nested calls use savepoints, with final durability and lock lifetime owned by the
outermost transaction. See ADR-003. The manual price equals the latest sequence's
amount and highest accepted bid. Same-auction writers serialize across sessions;
other auction rows are independent. No FIFO, fairness or global order is promised.

Application clocks and explicit lifecycle actions remain; synchronized clock
policy, closing workers and soft-close are Phase 4. Idempotent retries are Phase 5.
Unexpected database failures are not broadly retried or masked as domain errors.

Reads do not hold a multi-query snapshot. Auction price and computed active leader
may be read across different commits during traffic. Committed database state is
consistent, but a multi-query HTTP view is not promised snapshot consistency.
