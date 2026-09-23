# Architecture

## Phase 0 scope

The executable foundation is a Next.js presentation application in
`apps/web`, a Rails API application in `apps/api`, and PostgreSQL. See
[progress](progress.md) for verification status. No domain models exist yet.

The initial page is static. It does not call a business API. Rails exposes a
liveness endpoint at `/up`; this confirms application boot, not database readiness.
Database connectivity is checked separately with ActiveRecord and PostgreSQL probes.

## Boundaries

Rails will own all authoritative business rules and persistence. Next.js owns
presentation. PostgreSQL will coordinate concurrent authoritative writes across
Rails processes. There are no services, repositories, or domain modules invented
in advance of real use cases. See [ADR-001](adr/001-modular-monolith.md).

## Later phases — not implemented

Phase 1 adds the core domain. Later phases add bid serialization, automatic bidding,
closing, idempotency, and the auction UI. Action Cable arrives in Phase 7;
Redis/Sidekiq in Phase 8; outbox in Phase 9; Kafka in Phase 10. Projections,
reconciliation, observability, load testing, and deployment follow the master plan.
These are requirements for later work, not current capabilities.
