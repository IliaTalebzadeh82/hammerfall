# Architecture

## What exists now — Phases 0–2

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
workflow rules inside a PostgreSQL transaction with SELECT FOR UPDATE on one auction.
Fresh validation, auction-local sequence assignment, bid insertion and price update
share that lock. Existing lifecycle/draft actions follow the same protocol. See
[ADR-003](adr/003-auction-concurrency-control.md). Waiters consume database connections;
a hot auction is intentionally serialized. Other auctions can progress independently.
No process-local synchronization, external lock service or retry framework is used.

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
scripts verify the lifecycle and simultaneous HTTP bids against running containers.
Real PostgreSQL concurrency specs use committed rows and independent sessions.

## Later phases — not implemented

Automatic bidding follows in Phase 3; distributed closing/time authority and
soft-close in Phase 4; idempotency
in Phase 5; the auction frontend in Phase 6; Action Cable in Phase 7; Redis/Sidekiq
in Phase 8; outbox in Phase 9; Kafka in Phase 10. Projections, reconciliation,
observability, load testing, and deployment follow the master roadmap.
No component listed here is present merely because it appears in the future plan.
