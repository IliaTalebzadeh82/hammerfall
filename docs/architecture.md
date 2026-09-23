# Architecture

## What exists now — Phases 0 and 1

Next.js in apps/web serves the unchanged starting page. Rails in apps/api owns
User, Auction, Bid, explicit lifecycle operations, and a JSON REST API under
`/api/v1`. PostgreSQL stores all domain state. The frontend does not yet consume
the auction API. Compose still runs exactly web, api, and db.

```text
API client → /api/v1 controllers → Auction/User model operations → PostgreSQL
                 ↓                         ↓
           JSON presenters        Bid + current_price transaction

Browser → Next.js static starting page
```

Controllers validate request shape, locate the resource/actor, invoke explicit
model operations, and render intentional JSON. Small presenters define auction
and bid response fields. A shared API controller maps expected errors to a stable
envelope. There is no repository/service/use-case framework or state-machine gem.

Auction owns its lifecycle and bid-placement entry point. Bid guards accepted
history from ordinary mutations. SQL protects structural integrity; Ruby protects
workflow rules for sequential operations. The current-price/bid writes are atomic,
but no explicit locking, optimistic version, compare-and-swap, or other concurrency
coordination is implemented. See [ADR-002](adr/002-core-auction-state.md).

Identity is a supplied existing bidder_id, supported by minimal user create/list
endpoints for local demonstrations. It is not authenticated. Administrative-looking
lifecycle endpoints are also unauthenticated. This is not a deployable public API.

## Boundaries and health

Rails is the business authority; Next.js handles presentation; PostgreSQL owns
persisted state. [ADR-001](adr/001-modular-monolith.md) still governs service
boundaries. The in-database winner is exposed only after explicit closure. A current
leader is computed from the highest accepted bid and remains conceptually distinct.

`/up` is Rails liveness, not a database readiness guarantee. Compose separately
probes PostgreSQL. RSpec checks actual database connectivity, and the API smoke
script verifies the sequential lifecycle against running containers.

## Later phases — not implemented

Phase 2 adds concurrent bid serialization and authoritative ordering. Automatic
bidding follows in Phase 3; race-safe closing and soft-close in Phase 4; idempotency
in Phase 5; the auction frontend in Phase 6; Action Cable in Phase 7; Redis/Sidekiq
in Phase 8; outbox in Phase 9; Kafka in Phase 10. Projections, reconciliation,
observability, load testing, and deployment follow the master roadmap.
No component listed here is present merely because it appears in the future plan.
