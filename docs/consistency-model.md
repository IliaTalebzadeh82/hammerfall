# Consistency model

PostgreSQL stores User, Auction, Bid, current price, sequence, private maxima/priority, explicit leader and closed-auction
winner. Phase 11 has an optional, explicitly eventual Redis public projection;
the frontend still renders PostgreSQL-backed REST state that can become stale between refreshes.

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

## Phase 7 invalidation consistency

PostgreSQL transactions and row locks remain authoritative. Action Cable's
PostgreSQL adapter transports ephemeral revision hints across application processes.
The notification runs after the outermost commit, so an independent reader can see
its revision. A crash between commit and broadcast loses the hint; connection loss
has no replay. Confirmation/reconfirmation always triggers REST recovery. A live
socket does not imply current state or database health. Auction/history GETs remain
separate observations and may straddle another commit. See realtime.md and ADR-008.

## Phase 8 job consistency (historical enqueue path)

After commit, Sidekiq carries a public ID/revision hint and reads current
PostgreSQL revision before broadcasting. Delayed/reordered jobs do not regress
the hint, but enqueue loss and exhausted retries can leave clients stale. The
periodic sweep checks selected PostgreSQL cross-row facts read-only; it is not a
Redis projection and cannot repair authoritative drift. This historical queue
path has no cache consistency guarantee. See ADR-009.

## Phase 9 publication consistency

The public revision and its outbox intent commit together. A publisher claims
only committed rows, so an API crash after commit or Redis outage before enqueue
cannot permanently erase that intent. Retry and concurrent publishers can
duplicate or reorder notifications; each job reads the latest PostgreSQL revision
and asks the browser to GET. Queue acknowledgment is not final Cable delivery.
Redis loss after acknowledgment, exhausted job retries and missed sockets still
require REST recovery. No global order, bounded freshness or exactly-once
guarantee exists. See ADR-010 and the failure model.

## Phase 10 Kafka propagation consistency

The same committed row carries a public domain snapshot and independent Kafka
delivery state. Kafka and Sidekiq publisher attempts can diverge without
changing auction truth. Kafka broker acknowledgment is earlier than consumer
effect/offset acknowledgment. The audit consumer's PostgreSQL receipt and
entry commit together; replay is a no-op. Its first/next/gap/stale labels
describe arrival order, not authoritative auction state. A poison record blocks
its partition until operator action. See ADR-011 and the Kafka runbook.

## Phase 11 Redis projection consistency

The Kafka projection group accepts only public v1 envelopes. A Lua comparison
atomically applies a higher `public_revision`, treats equal data as duplicate,
discards lower revisions and stops on same-revision conflicting data. Offset
commit follows the Redis effect; crash replay is harmless for equal content.
These rules prevent accepted older events from regressing a newer key, including
a key seeded from current PostgreSQL state. They do not make Redis current.
The explicit `/public-state` response identifies Redis source, event age and
projection write time. A missing, invalid or unavailable key falls back to a
current PostgreSQL public read and labels it accordingly. A well-formed but
stale key remains an eventual result. Redis loss after offset acknowledgment
requires a manual PostgreSQL rebuild; finite Kafka retention is insufficient
as a general recovery guarantee. See ADR-012 and the projection runbook.
