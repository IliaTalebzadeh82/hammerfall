# ADR-008: Realtime auction invalidations

Status: Accepted — Phase 7, 2026-09-29

## Context

Phase 6 discovers other bidders' changes only on refresh. We need cross-process
notifications without making delivery part of bidding correctness or adding Redis.
PostgreSQL remains authority; REST describes current public state. An accepted
command and a current auction snapshot remain different facts.

## Decision

Use Action Cable's PostgreSQL subscription adapter (LISTEN/NOTIFY), not Solid Cable
or process-local async. Isolated specs use the test adapter; live verification must
use PostgreSQL through two independent Rails servers. One public AuctionChannel
validates an existing positive bigint ID and streams `auction:<id>`, independent of
demo actor identity. Explicit allowed origins retain origin protection.

Messages have exactly three public fields:

```json
{"type":"auction.changed.v1","auction_id":42,"revision":17}
```

No prices, descriptions, bids, maxima, priorities, origins, keys, or command results
travel over Cable. This is a tiny invalidation protocol, not a domain-event API.

Auction.public_revision is a nonnegative bigint starting at zero for creation and
legacy rows. Each logical public edit/lifecycle/bidding mutation increments once
under the existing row lock in the same transaction. Multiple proxy rows and an
extension still mean one increment. Private-only protection increases, identical
maxima, rejected commands, early/duplicate closes, unchanged edits, replay and
pruning increment nothing. Initial creation establishes revision zero; there is no
listing subscription requiring a creation notification. Normal term edits must use
the existing explicit draft operation; privileged SQL bypasses remain outside the
workflow contract. No public timestamp changes for a private-only mutation.

The explicit public-save helper schedules one publication via the current Rails
transaction's after_commit. Savepoint callbacks transfer to the parent and are
removed on rollback. Capture scalar ID/revision, not a mutable model. One publisher
owns the broadcast call and catches/logs publication failures after commit without
turning a committed command into a failed business action. Several distinct commands
in a caller-owned outer transaction each retain their own revision/invalidation.

The detail page uses one Cable subscription, removed on unmount/auction change.
Confirmation and reconfirmation always request REST state to close the GET-to-
subscribe gap and recover missed notifications. Revision hints never edit state or
resolve pending commands. Stale/equal hints are ignored. A small refresh coordinator
coalesces in-flight hints, remembers the highest requested revision, and follows up
only when needed. REST revision prevents regression. Explicit/command/focus refresh
remains available independently of transport, including after refresh failure.
Listing retains its bounded REST pagination/explicit refresh model.

## Delivery and recovery limits

Delivery is best-effort and ephemeral. A process can commit, then crash before
broadcast. PostgreSQL NOTIFY is not a retained event log. A connected socket is not
proof that REST/database is healthy or state is permanently fresh. Manual, focus,
command and subscription-confirmation refresh recover current state; there is no
replay, durable queue, outbox or reconciliation subsystem. Separate auction/history
GETs can straddle commits; refreshed history is still not an atomic snapshot.

## Alternatives Considered

- Polling only: simpler but delays other bidders' changes or creates periodic reads.
- SSE: viable unidirectional invalidation, but the roadmap chooses Action Cable.
- async adapter: process-local; cannot carry A's change to B's socket.
- Redis adapter: viable later, introduces Phase 8 infrastructure now.
- Full snapshots: larger payloads, privacy and ordering risks, NOTIFY size constraints.
- Per-Bid events: duplicates one logical contest and misses lifecycle/extension-only changes.
- Client-applied domain events: duplicates auction semantics and misrepresents proxy outcomes.
- updated_at: timestamp ties and private/unrelated writes are unsuitable public ordering.
- Bid sequence: does not advance for closing, cancellation or protection-only extension.
- Kafka/outbox now: durability is valuable but explicitly deferred to later phases.

## Consequences and risks

Each connected Rails process adds a dedicated PostgreSQL listener connection outside
its ordinary pool; subscriptions and broadcasting also use pooled connections.
Cable workers and HTTP threads share bounded database capacity. Invalidation adds
REST read amplification and hot-auction fanout. No capacity/performance claim or
final production architecture follows. Actor IDs and lifecycle APIs remain
unauthenticated; the channel contains public information only. Lost notifications
can leave a connected browser stale until another recovery trigger.

## Revisit When

Redis, outbox/Kafka, measured fanout/read amplification, authentication, multi-region
writes, or standalone Cable scaling arrive. Revision resets/downgrades require
stopping clients and preserving metadata; never silently reinterpret a live revision.

Framework references: [Action Cable guide](https://guides.rubyonrails.org/action_cable_overview.html)
and [transaction callbacks](https://api.rubyonrails.org/classes/ActiveRecord/Transaction.html).
Implementation was also checked against installed Rails 8.1.3.1 adapter/transaction source.

Phase 8 follow-up: [ADR-009](009-sidekiq-public-notifications-and-sweeps.md)
keeps this public protocol and PostgreSQL Cable adapter, but the after-commit
callback now enqueues a Sidekiq job, which performs the broadcast asynchronously.
This ADR describes the original Phase 7 direct-publication decision.
