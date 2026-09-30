# Auction state, persistence and ordering

## Core model

User is a deliberately simple bidder identity. Auction stores title/description, draft/scheduled/active/closed/cancelled status, starting/current integer-cent price, minimum increment, start/effective/original end, current leader, final winner and public revision. Bid is an accepted immutable public-price fact with auction/bidder, amount, auction-local sequence and timestamp; internal origin is manual/automatic. MaximumBid is a private per-bidder ceiling and priority. IdempotencyRecord and OutboxEvent exist now. The outbox stores public publication intent in the same transaction as each public revision. See [domain model](../domain-model.md), [schema](../../apps/api/db/schema.rb) and [API](../api.md).

## Invariants and transaction semantics

- Explicit lifecycle operations govern transitions. An active auction accepts decisions only in its time window; closed/cancelled auctions cannot accept bids. Closing sets at most one authoritative winner, copied from the settled leader. A browser or read model must not contradict PostgreSQL about a winner.
- Every accepted bid belongs to one auction. Auction-local positive unique `sequence` gives deterministic accepted ordering; timestamps, browser clocks, WebSocket arrival and IDs are not authority. A public price and current leader are stored with accepted history under one auction transaction.
- All application writers of authoritative auction state use the same PostgreSQL auction row lock before reading and changing it. This prevents lost updates across Rails processes and serializes bidding against close/edit/lifecycle actions. Waiters can consume connections; one hot auction is intentionally a bottleneck. Lock acquisition is not FIFO. For any future multi-auction operation, lock auctions in ascending ID order.
- SQL constraints defend structural facts; explicit Ruby operations enforce cross-row workflow. Migrations must be clear, safe and reversible where practical. Plan preservation and rollout for destructive or non-backward-compatible changes. Index and inspect important auction, bid-history, maximum, close-candidate, outbox and reconciliation queries; use `EXPLAIN ANALYZE` when useful.
- PostgreSQL is authoritative even if Redis is empty, Kafka is unavailable or an app process restarts. A derived view must have a detectable freshness/version contract before it can be used.

## Interfaces and decisions

The API uses `/api/v1` REST, bounded pagination and consistent public error envelopes. [ADR-002](../adr/002-core-auction-state.md) and [ADR-003](../adr/003-auction-concurrency-control.md) record the model and lock choice. [Invariants](../invariants.md) is the implementation-level inventory and must evolve with the schema. There is no authentication yet; supplied bidder IDs are demo identity, not authority.
