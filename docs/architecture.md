# Architecture

## What exists now — Phases 0–7

Next.js in apps/web provides the auction listing/detail and command UI. Rails in apps/api owns
User, Auction, Bid, MaximumBid, explicit lifecycle operations, and a JSON REST API under
`/api/v1`. PostgreSQL stores all domain state. The frontend consumes the versioned REST API through a transparent same-origin
rewrite; Rails remains the sole command authority. Compose runs web, api, db and auction-closer.

```text
API client → controllers → IdempotentBidding (bid/max) → Auction → PostgreSQL
                       → other User/Auction operations → PostgreSQL
                 ↓                         ↓
           JSON presenters        Bid + current_price transaction

Browser / Next.js → REST reads and commands → Rails API → PostgreSQL
Browser ← public revision hint ← Rails Cable B ← PostgreSQL NOTIFY ← Rails A after commit

Auction Closer (same Rails app/process role) → Auction#close! → PostgreSQL
```

Controllers validate request shape and render intentional JSON. Protected bid/max
commands resolve the actor, then IdempotentBidding claims the key before locating
the auction or invoking its model operation. Other endpoints call models directly. Small presenters define auction
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
boundaries. The in-database winner is exposed only after authoritative closure. A current
leader is stored explicitly after proxy resolution, separately from winner.

`/up` is Rails liveness, not a database readiness guarantee. Compose separately
probes PostgreSQL. RSpec checks actual database connectivity, and the API smoke
scripts verify the lifecycle and simultaneous HTTP bids against running containers.
Real PostgreSQL concurrency specs use committed rows and independent sessions.

## Later phases — not implemented

Redis/Sidekiq in Phase 8; outbox in Phase 9; Kafka in Phase 10. Projections, reconciliation,
observability, load testing, and deployment follow the [phase specifications](phases/phase-08.md).
No component listed here is present merely because it appears in the future plan.


## Proxy bidding

Auction#place_bid! and #set_maximum! own transaction/lock/eligibility boundaries.
Bidding::ProxyResolver owns the complete pairwise pricing algorithm and ordered
visible bid generation. Private MaximumBid records have their own priority order.
The auction leader/price and all generated bids are updated before the single commit;
there is no intermediate committed challenger followed by an asynchronous counter.
MaximumBidsController acknowledges writes without exposing private state. Public
presenters never expose maximum/priority/origin. ADR-004 records the decision table,
settled-state proof, binding policy and representation-versus-authorization limit.

## Deadline authority and closer

AuctionClock reads uncached PostgreSQL clock_timestamp() after the auction row
lock. AuctionDeadline contains pure half-open deadline and final-60/+90 arithmetic.
Auction persists extension with each accepted command's complete settlement.
Auction#close! finalizes if due and copies leader to winner without another Bid.
The closer is a separate process role of this modular Rails app, not a microservice:
no API hop or separate datastore sits between it and the same domain operation.

AuctionCloser discovers bounded active/due IDs using the partial (ends_at,id) index,
then revalidates each under the domain lock. Discovery is not authority. Multiple
closers safely overlap; there is no leader election. Delayed polling leaves status
active temporarily, but bid/max deadline checks still reject. We do not lazily
finalize through rejected bidding transactions. Poll interval is not a closure SLA.
See ADR-005 and running-locally.md for failure and shutdown behavior.

## Client retry boundary — Phase 5

```text
Next.js browser UI (request/response + explicit refresh)

HTTP clients -> Rails API instances
                  |
             IdempotentBidding / Idempotency::Executor
                  |
                  +-- PostgreSQL idempotency_records ownership + terminal snapshot
                  |
                  +-- same transaction -> Auction row -> bids/maxima/extension

Auction Closer -> same Rails Auction#close! -> same PostgreSQL
```

This is an application/database capability, not another service. Thin controllers
parse key/command/IDs and render the returned outcome. Executor owns scoped claim,
fingerprint, replay/conflict and outer commit. Existing Auction savepoints preserve
complete domain rollback. Duplicate INSERTs coordinate via PostgreSQL uniqueness;
completed retries bypass Auction entirely. No mutex, Redis or generic middleware
pipeline exists. A manual bounded prune task manages expired completed outcomes.
See ADR-006 for lock order, failure classes, retention and compatibility boundaries.

## Browser boundary — Phase 6

App Router pages use one client REST layer with public runtime shape guards. Local
read/form state stays in each view; one context shares the demo actor and unresolved
command. A transparent Next rewrite provides local connectivity, without Next API
handlers, BFF domain logic or wildcard production CORS.

One opaque key and immutable payload are saved in sessionStorage before transmission.
Transport ambiguity retains them for explicit safe retry; terminal responses trigger
fresh auction/history reads. No optimistic price, leader or local closure exists.
X-Server-Time is application-clock presentation metadata only. The ticking countdown
refreshes at zero and follows the returned effective deadline.

The Phase 7 detail page adds Action Cable invalidations through PostgreSQL
LISTEN/NOTIFY. Confirmation/reconfirmation and higher revisions request fresh REST
state. Explicit, visibility, command and countdown refreshes remain independent.
See [realtime](realtime.md), frontend.md and ADR-008 for ordering and delivery limits.
