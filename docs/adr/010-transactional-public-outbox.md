# ADR-010: Transactional public outbox

Status: Accepted — Phase 9, 2026-09-30

## Context

Phase 8 committed auction state before its API process attempted a Redis enqueue.
A crash or Redis outage in that gap could permanently discard a public hint.
PostgreSQL remains the authority for auction state; Redis and Cable only improve
the freshness of public views.

## Decision

Every public auction mutation increments `public_revision`, saves the auction,
and inserts one `auction.changed.v1` outbox row inside the same PostgreSQL
transaction. The existing auction row lock serializes those changes. An enclosing
idempotency transaction commits the command outcome with them. A failed insert
or rollback removes all three; a replay, rejection, private-only change or no-op
inserts nothing. Initial draft creation starts at revision zero without an event.

The row has a stable UUID, event type, schema version 1, auction ID, public
revision, database occurrence timestamp, next-attempt time, attempt count,
last error class and enqueue acknowledgment time. A unique auction/revision
index prevents duplicate intent. There is no private payload. The envelope is
independent of Sidekiq's job format; a future transport can read committed rows
without moving the domain write boundary.

An independent `outbox-publisher` process selects due rows using PostgreSQL
`FOR UPDATE SKIP LOCKED`. It holds a row lock while attempting Redis enqueue,
then records `published_at` only after Sidekiq returns a job ID. Client Redis
network operations have a two-second timeout, without a strict total cycle
deadline. A failure stores its class
and an exponential delay capped at 300 seconds; retries continue indefinitely.
Each cycle logs aggregate backlog, due, retry and oldest-age values. Operators
must inspect repeatedly failing rows; rows are never silently discarded.
Retry and acknowledgment timestamps and pending age use PostgreSQL clock time,
matching the database due predicate even if publisher hosts have clock skew.

## Consequences and limits

The outbox closes the API commit-to-enqueue loss window. A dead API or publisher
leaves committed, unpublished work discoverable. A crash after Redis accepted a
job but before PostgreSQL acknowledgment can enqueue it again. Different rows,
even for one auction, can be delivered out of order by multiple publishers.
`AuctionChangedJob` reads the current PostgreSQL revision and broadcasts only a
public invalidation; duplicate or stale jobs cannot regress auction state.

`published_at` acknowledges **Sidekiq enqueue**, not job completion, Cable
broadcast or browser receipt. Redis data loss after acknowledgment, exhausted
Sidekiq retries, Cable failure and a continuously connected stale browser can
still lose or miss a hint. REST is the recovery authority. No exactly-once,
global ordering, bounded delivery time or production capacity claim is made.
The occurrence timestamp is PostgreSQL transaction time, not an exact commit
timestamp. Long transactions can make reported pending age conservative.

## Alternatives

- Keep the after-commit callback and retry it in memory: a process crash still
  discards intent.
- Enqueue inside the auction lock: Redis delay holds the hot lock and cannot
  atomically commit with PostgreSQL.
- Serialize all publishers with a global lock: needless head-of-line blocking;
  row claims and revision-aware jobs already handle concurrency and reordering.
- Add Kafka event families now: Phase 10 owns that transport and its contracts.

See [the failure model](../failure-model.md), [event model](../event-model.md)
and [runbook](../runbooks/sidekiq-redis.md) for the operational contract.
