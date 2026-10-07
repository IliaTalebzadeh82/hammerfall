# Architecture

Hammerfall is a modular Rails auction application with a Next.js public client.
Rails decides auction commands; PostgreSQL stores the authoritative result.
Kafka transports committed public events, Redis holds a derived public
projection, Sidekiq performs operational work, and Action Cable sends public
revision hints. None of those downstream systems decides bid legality, price,
deadline or winner. The [case-study diagram](case-study.md#architecture-in-one-picture)
shows the command and propagation paths; [system boundaries](architecture/system-boundaries.md)
and [invariants](invariants.md) state the durable contract.

## Command and transaction path

Authenticated `/api/v1` bid and private-maximum requests derive the actor from
a PostgreSQL-backed session. They claim `(actor, operation, key)` through
`Idempotency::Executor` before locking the auction. `Auction#place_bid!` and
`#set_maximum!` then use one PostgreSQL row lock, sample uncached database time,
validate fresh state and settle proxy bids. Private changes commit with the
command; a changed public price, leader or deadline also commits its public
revision and outbox intent. The idempotency outcome commits in
the enclosing transaction. Replay returns its stored historical response; a
fresh GET supplies current state. Lifecycle and closer commands use the same
auction row lock. The closer rechecks the deadline under that lock and copies
the settled leader to winner only when reserve policy permits a sale.

[Auction state](architecture/auction-state.md), [bidding](architecture/bidding.md),
[deadlines](architecture/deadlines.md), [idempotency](architecture/idempotency.md)
and [ADR-003](adr/003-auction-concurrency-control.md) describe the rules and
lock order. A hot auction intentionally serializes writers and can consume
waiting database connections. The lock is not a FIFO arrival guarantee.

## Public delivery and recovery

Every public revision creates a public snapshot in the PostgreSQL outbox.
Independent publishers enqueue a Sidekiq invalidation job and deliver a Kafka
event. The Kafka audit consumer writes a durable event-ID receipt and public
audit effect before committing its offset. A separate consumer applies the
event to Redis with revision and digest guards. Duplicate or reordered
delivery cannot change authoritative auction state. The ordinary auction GET
reads PostgreSQL; the explicit eventual read may serve Redis or fall back to
PostgreSQL. Reconciliation safely seeds missing or older projections and
escalates ahead, conflicting or corrupt state for review. See
[async events](architecture/async-events.md) and
[projections](architecture/projections-and-reconciliation.md).

Action Cable carries only a revision hint. The browser responds with a fresh
REST read and retains an immutable command key and payload across ambiguous
transport failure. See [realtime/frontend](architecture/realtime-and-frontend.md).
After PostgreSQL PITR, old Kafka/Redis/Sidekiq may contain a discarded future;
the [recovery runbook](runbooks/database-recovery.md) fences traffic, quarantines
old Kafka, rebuilds derived state and replays retained outbox intent. The
[local game day](operations/phase-22-final.md#integrated-local-game-day) proves
that procedure only in its recorded environment.

## Security, operations and evidence

Sessions, CSRF, authorization, seller self-bid prevention, request limits and
HMAC idempotency digests guard the public command boundary. The internal
operator API is disabled by default and exposes only bounded diagnosis and
projection reconciliation to operators. `RECOVERY_FENCE` is a process-local
defense in depth, not a distributed maintenance lock. [Security and operations](architecture/operations-and-security.md)
and [production-readiness limits](production-readiness.md) state what remains
unverified.

The [code map](code-map.md) routes to implementation and tests. The
[case study](case-study.md) selects the three strongest experiments. Local
Compose, Kubernetes and the static GCP reference are different verification
levels; none implies production capacity or managed-service recovery.
