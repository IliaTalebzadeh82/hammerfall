# HAMMERFALL — MASTER ENGINEERING PROMPT

You are the lead engineer responsible for designing and implementing **Hammerfall**, a production-grade real-time auction platform built as a serious distributed-systems portfolio project.

This is not a tutorial application.

This is not a CRUD marketplace.

This is not a visual clone of Catawiki.

The goal is to build a technically credible auction system demonstrating strong engineering judgment around:

- concurrency
- transactional correctness
- distributed systems
- real-time communication
- asynchronous messaging
- idempotency
- consistency models
- failure recovery
- reconciliation
- observability
- scalability
- performance testing
- infrastructure
- operational maturity

The system should be technically interesting enough that an experienced backend, platform, or distributed-systems engineer could inspect the repository and find substantial engineering depth.

The final repository should feel like a small but serious production system.

---

# 1. PRIMARY PRODUCT IDEA

Hammerfall is an online auction system focused specifically on the hard engineering problems behind high-contention auctions.

Users can:

- browse auctions
- inspect an auction
- place bids
- configure automatic maximum bids
- observe live bid activity
- see countdowns and auction extensions
- win or lose auctions
- inspect auction history

Administrators/operators should have a minimal operational interface for:

- inspecting auctions
- inspecting bid history
- seeing auction state
- seeing reconciliation status
- inspecting failed background/event processing
- understanding degraded system state

The product domain is intentionally narrow.

Do not spend large amounts of effort building unrelated marketplace functionality.

Avoid unless later justified:

- seller onboarding
- shipping systems
- messaging
- reviews
- recommendation engines
- elaborate user profiles
- social features
- complex payments
- catalog management systems

The engineering focus is the auction lifecycle.

---

# 2. CORE ENGINEERING QUESTION

The project should answer:

> How do we guarantee a correct auction outcome when many users concurrently bid near the closing time while application instances, caches, message brokers, asynchronous consumers, and real-time clients can fail or observe different versions of reality?

Everything in the architecture should support exploring this question.

---

# 3. TECHNOLOGY STACK

Use the following stack unless a later architectural decision explicitly justifies a change.

## Backend

- Ruby
- Ruby on Rails
- Rails API architecture where appropriate
- ActiveRecord
- PostgreSQL
- RSpec

Ruby/Rails must contain the authoritative auction business logic.

Do not move critical auction logic to Go, Node.js, or another language.

---

## Frontend

- TypeScript
- React
- Next.js
- shadcn/ui
- Tailwind CSS

Use shadcn/ui for common UI primitives.

The frontend should be polished and usable, but UI aesthetics must never consume more engineering effort than auction correctness.

---

## Real-time communication

Initially:

- Rails Action Cable
- WebSockets

Later architecture may evolve if testing demonstrates a concrete limitation.

Do not prematurely introduce another dedicated socket service.

---

## Database

PostgreSQL is the authoritative source of truth.

It owns authoritative state for:

- auctions
- bids
- automatic bid configurations
- winning state
- idempotency records
- auction lifecycle transitions
- transactional outbox entries

Use PostgreSQL features deliberately:

- transactions
- row locking
- isolation
- constraints
- indexes
- unique constraints
- timestamps
- potentially advisory locks if justified

---

## Background jobs

Use:

- Redis
- Sidekiq

Use Sidekiq for application-level asynchronous work such as:

- notifications
- reconciliation jobs
- operational maintenance
- non-authoritative scheduled work

Do not treat Sidekiq and Kafka as interchangeable.

Document why each is used.

---

## Event streaming

Use:

- Apache Kafka

Kafka should be introduced only after the core transactional auction system works.

Kafka should support asynchronous domain/event propagation.

Examples:

- bid.accepted
- auction.extended
- auction.closed
- auction.won

Use a transactional outbox so domain-state changes and event publication cannot diverge due to an application crash between database commit and broker publication.

Kafka is not the source of truth for auction correctness.

PostgreSQL remains authoritative.

---

## Read models / caching

Use Redis selectively.

Possible uses:

- real-time projections
- ephemeral cached auction views
- rate limiting
- connection/presence information
- temporary read optimization

Redis must never determine the authoritative auction winner.

The system must remain correct if Redis loses all data.

---

## Observability

Use:

- OpenTelemetry
- OpenTelemetry Collector
- Prometheus
- Grafana
- Grafana Tempo
- structured JSON logging
- optionally Loki when useful

Instrument:

- HTTP requests
- bidding workflow
- PostgreSQL interaction
- lock wait time
- Kafka producer operations
- Kafka consumer operations
- Sidekiq jobs
- WebSocket update delivery
- reconciliation
- auction closure
- automatic bidding

Observability must be designed intentionally, not added as decoration.

---

## Testing

Backend:

- RSpec

Frontend:

- Vitest
- React Testing Library

End-to-end:

- Playwright

Load testing:

- k6

Write meaningful concurrency and integration tests.

---

## Local environment

Use:

- Docker
- Docker Compose

The repository should eventually support a straightforward local environment.

---

## CI

Use:

- GitHub Actions

CI should eventually perform:

- linting
- backend tests
- frontend tests
- integration tests where practical
- image builds
- static checks

---

## Deployment

Later phases:

- Kubernetes
- Terraform
- GCP

Do not introduce Kubernetes during initial development.

First prove the application locally and under multiple processes/containers.

---

# 4. INITIAL ARCHITECTURAL PRINCIPLE

Start as a **modular Rails application**, not as a collection of microservices.

The project must demonstrate that architectural complexity is introduced because of requirements rather than fashion.

Initial architecture:

```text
Browser
   │
   ▼
Next.js
   │
HTTP/WebSocket
   │
   ▼
Rails application
   │
   ▼
PostgreSQL
```

Later:

```text
                       ┌───────────────────┐
                       │     Next.js       │
                       └─────────┬─────────┘
                                 │
                         HTTP / WebSocket
                                 │
                       ┌─────────▼─────────┐
                       │       Rails       │
                       │ Auction Platform  │
                       └─────────┬─────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
                PostgreSQL     Redis       Sidekiq
                    │
                    │ transactional outbox
                    ▼
                  Kafka
                    │
          ┌─────────┼─────────────┐
          │         │             │
          ▼         ▼             ▼
     projections notifications analytics/events
```

Do not extract services unless a concrete reason exists.

Possible valid reasons:

- independent scaling
- substantially different availability requirement
- independent deployment lifecycle
- ownership boundary
- fundamentally different workload
- fault isolation

Whenever extraction happens, create an ADR explaining why.

---

# 5. REQUIRED DOMAIN MODEL

At minimum, model:

## User

Represents bidders.

Keep user identity intentionally simple.

---

## Auction

An auction should include concepts such as:

- identifier
- title
- description
- status
- starting price
- current authoritative price
- minimum increment
- starts_at
- ends_at
- original_ends_at
- winner
- version/state metadata as needed

Possible statuses:

```text
draft
scheduled
active
closed
cancelled
```

Define allowed transitions explicitly.

---

## Bid

A bid should capture:

- bidder
- auction
- amount
- authoritative sequence/order
- accepted/rejected semantics where appropriate
- timestamp
- idempotency information
- origin:
  - manual
  - automatic

Never depend solely on client timestamps for authoritative ordering.

---

## AutomaticBid

A user may specify a private maximum.

Example:

```text
Current price: €100

Alice max: €300
Bob bids: €200
```

The system may automatically increase Alice's visible bid according to auction rules while keeping her maximum private.

The implementation must handle multiple competing automatic bidders correctly.

---

## OutboxEvent

Contains domain events awaiting publication.

---

## IdempotencyRecord

Supports safe retry behavior for operations such as placing bids.

---

# 6. DOMAIN INVARIANTS

The system must explicitly document and enforce invariants.

At minimum:

1. A closed auction cannot accept a new bid.

2. A bid request with the same idempotency key cannot create multiple bids.

3. Every accepted bid belongs to exactly one auction.

4. An auction can have at most one authoritative winner.

5. Accepted bids have a deterministic authoritative ordering.

6. Client timestamps cannot determine authoritative ordering.

7. The visible auction state must never claim a winner that contradicts PostgreSQL authoritative state.

8. Automatic bid maximum values are private.

9. Two concurrent requests must not result in lost updates.

10. Auction closure and bid acceptance must be serialized correctly.

11. A committed accepted bid must eventually produce its corresponding domain event.

12. Duplicate event delivery must not create duplicate downstream effects.

13. Read-model inconsistency must be detectable.

14. Read-model inconsistency must be repairable.

15. Redis loss must not invalidate authoritative auction state.

Document all invariants in:

```text
docs/invariants.md
```

Update this document whenever the model evolves.

---

# 7. AUCTION ORDERING

Design an authoritative ordering mechanism for accepted bids.

Consider:

- database sequence
- monotonically increasing auction-local sequence
- transaction ordering
- created_at only as observational metadata

Do not use:

```text
browser clock
client-generated timestamp
arrival order at WebSocket layer
```

as authoritative ordering.

Document the chosen model.

---

# 8. CONCURRENT BIDDING

One of the central goals of Hammerfall is correctness under contention.

Example:

```text
Current price: €4,800

Alice -> €5,000
Bob   -> €5,200
Carol -> €5,100
David -> €5,400
```

These requests may reach different Rails processes simultaneously.

The system must maintain deterministic state.

Explore and document concurrency approaches such as:

- pessimistic row locking
- optimistic locking
- compare-and-swap style state transitions
- database constraints

Implement one intentionally.

Later benchmark alternatives where valuable.

Create:

```text
docs/adr/auction-concurrency-control.md
```

Explain:

- context
- options
- trade-offs
- decision
- consequences

---

# 9. AUTOMATIC BIDDING

Implement maximum/automatic bidding.

Example:

```text
Auction current price: 100
Increment: 10

Alice maximum: 300
Bob maximum: 240
```

The visible price should evolve according to defined auction rules while Alice's maximum remains secret.

Define behavior for:

- same maximum from multiple users
- previous maximum bidder vs new maximum bidder
- simultaneous automatic bid updates
- manual bid above existing maximum
- manual bid equal to an existing maximum
- automatic-bid modification
- automatic-bid cancellation if supported
- auction close during automatic-bid competition

All behavior must be tested.

---

# 10. AUCTION CLOSING

Implement authoritative closing semantics.

A naive implementation such as:

```ruby
if Time.now > auction.ends_at
```

running independently on multiple nodes is insufficient.

Define:

- authoritative time source
- who transitions auctions to closed
- what happens if closure and bidding race
- what happens if closure jobs run multiple times
- what happens after scheduler delays
- how stale workers behave
- whether closure is job-driven, request-driven, DB-driven, or hybrid

Closure must be idempotent.

Document in:

```text
docs/adr/auction-closing.md
```

---

# 11. SOFT-CLOSE / ANTI-SNIPING

Implement auction extension rules.

Example policy:

```text
If an accepted bid occurs within the final 30 seconds,
extend the auction by 30 seconds.
```

The exact values may be configurable.

Handle:

- simultaneous final-second bids
- repeated extensions
- automatic bids during extension
- stale clients showing old end times
- race between closing and extension

Expose extension events to clients in real time.

---

# 12. IDEMPOTENCY

Bid placement must support:

```http
Idempotency-Key: <uuid>
```

Retries with the same logical request must not create multiple bids.

Handle:

- duplicate concurrent requests
- retry after network timeout
- same key with different request payload
- expiration/retention strategy
- transaction behavior

Document semantics.

---

# 13. TRANSACTIONAL OUTBOX

Never implement:

```text
write DB
publish Kafka
```

as two independent operations.

Instead:

```text
BEGIN

change auction state
insert bid
insert outbox event

COMMIT
```

A publisher later sends outbox entries to Kafka.

Handle:

- publisher crash
- duplicate publication
- Kafka unavailable
- database transaction rollback
- retry
- event IDs
- event ordering

Consumers must tolerate duplicate delivery.

---

# 14. DOMAIN EVENTS

Use explicit versioned event schemas.

Examples:

```text
bid.accepted.v1
auction.extended.v1
auction.closed.v1
auction.won.v1
```

Event payloads should contain:

- event_id
- event_type
- schema_version
- aggregate_id
- aggregate_version or sequence
- occurred_at
- relevant domain payload
- trace/correlation context where appropriate

Do not leak sensitive data unnecessarily.

Document schemas.

---

# 15. REAL-TIME UX

Clients should see live auction state.

Use Action Cable initially.

Support:

- bid accepted
- current price change
- countdown extension
- auction closure
- connection state
- stale state recovery

The browser must treat WebSocket data as a projection, not unquestionable authority.

After reconnect:

```text
fetch authoritative/current projection
reconcile local state
resume updates
```

Handle stale bid attempts gracefully.

Example:

Browser sees:

```text
€4,800
```

Server is already:

```text
€5,000
```

User submits:

```text
€4,900
```

Response should communicate:

```json
{
  "error": "bid_too_low",
  "current_price": 5000,
  "minimum_next_bid": 5100
}
```

The frontend must reconcile.

---

# 16. FRONTEND EXPERIENCE

Build a polished but focused experience.

Primary auction screen should include:

- auction title
- current price
- next valid bid
- bid form
- auto-bid controls
- auction countdown
- real-time connection indicator
- bid history
- winning/outbid state
- auction extension feedback
- closed state

Use shadcn/ui primitives.

Possible components:

- Button
- Card
- Dialog
- Sheet
- Table
- Tabs
- Badge
- Alert
- Toast
- Input
- Skeleton
- Tooltip

Make responsive behavior good enough for desktop and mobile.

Do not spend weeks on decorative visual effects.

---

# 17. READ MODELS

Introduce read models once there is a concrete reason.

PostgreSQL remains authoritative.

Redis may hold a fast auction projection.

Example:

```text
PostgreSQL:

winner = Alice
price = 5000

Redis:

winner = Bob
price = 4800
```

The system must be able to detect this inconsistency.

---

# 18. RECONCILIATION

Implement a reconciliation subsystem.

Possible component:

```text
AuctionConsistencyChecker
```

It periodically verifies projections against authoritative PostgreSQL state.

Detect metrics such as:

```text
auction_projection_drift_total
auction_projection_repair_total
auction_projection_repair_failure_total
```

Repair stale read models safely.

Produce structured logs describing repairs.

Document:

- what gets compared
- what is repairable automatically
- what requires operator intervention
- repair idempotency

This is a first-class system capability.

---

# 19. SIDEKIQ

Use Sidekiq for things such as:

- notification jobs
- scheduled reconciliation
- cleanup jobs
- operational maintenance

Every Sidekiq job must be safely retryable.

Where duplicate execution could cause harm, make jobs idempotent.

---

# 20. KAFKA CONSUMERS

Build one or more meaningful consumers.

Examples:

## Auction projection consumer

Updates Redis/read state from events.

## Notification consumer

Creates notification work when relevant.

## Audit consumer

Maintains append-only derived audit state where useful.

Consumers must handle:

- duplicate messages
- retry
- poison messages
- ordering
- consumer restarts
- replay

Do not claim "exactly once" unless truly justified.

Prefer explicit at-least-once semantics.

---

# 21. FAILURE MODEL

Create:

```text
docs/failure-model.md
```

Document expected behavior when:

- PostgreSQL is unavailable
- Redis is unavailable
- Kafka is unavailable
- Sidekiq worker crashes
- Kafka consumer crashes
- Rails instance crashes
- WebSocket connection drops
- event publication is delayed
- duplicate Kafka event arrives
- network latency spikes
- auction-closing worker runs late
- two closing workers run concurrently

For each case define:

```text
What remains correct?
What becomes unavailable?
What becomes stale?
How does recovery happen?
```

---

# 22. OBSERVABILITY

Instrument the system properly.

Use OpenTelemetry.

Create meaningful traces.

Example:

```text
POST /auctions/:id/bids

HTTP server span
    |
    +-- load auction
    |
    +-- acquire auction lock
    |
    +-- validate bid
    |
    +-- resolve automatic bidding
    |
    +-- insert bid(s)
    |
    +-- update auction
    |
    +-- create outbox event
    |
    +-- commit
```

Kafka traces should continue trace context where practical.

---

# 23. METRICS

Expose useful Prometheus metrics.

Examples:

```text
hammerfall_bid_requests_total

hammerfall_bid_accepted_total

hammerfall_bid_rejected_total{reason}

hammerfall_bid_processing_duration_seconds

hammerfall_auction_lock_wait_duration_seconds

hammerfall_auction_extensions_total

hammerfall_auction_close_lag_seconds

hammerfall_outbox_pending_events

hammerfall_outbox_oldest_event_age_seconds

hammerfall_outbox_publish_failures_total

hammerfall_kafka_consumer_lag

hammerfall_projection_drift_total

hammerfall_projection_repair_total

hammerfall_websocket_delivery_lag_seconds
```

Avoid uncontrolled label cardinality.

Never put:

```text
user_id
auction_id
email
bid_id
```

directly into metric labels unless there is an extremely strong bounded-cardinality reason.

---

# 24. LOGGING

Use structured JSON logging.

Include bounded context such as:

```text
trace_id
span_id
operation
auction_state
result
error_type
```

Avoid leaking:

- authentication tokens
- private automatic-bid maximums
- passwords
- secrets
- personal information unnecessarily

---

# 25. DASHBOARDS

Create Grafana dashboards.

At minimum:

## Auction health

- bid rate
- bid latency
- rejection reasons
- auction closing delay
- extensions

## Messaging

- pending outbox
- publish latency
- Kafka failures
- consumer lag

## Consistency

- detected drift
- repaired drift
- failed repair
- stale projection age

## Runtime

- HTTP latency
- error rate
- PostgreSQL performance
- job failures

Dashboards should answer operational questions, not merely display every available metric.

---

# 26. LOAD TESTING

Use k6.

Create scenarios including:

```text
normal-auction.js
hot-auction.js
final-minute.js
duplicate-retries.js
websocket-fanout.js
```

Important scenario:

```text
1000 concurrent bidders
one hot auction
final 10 seconds
hundreds of competing bids
```

Measure:

- accepted bids
- rejected stale bids
- p50
- p95
- p99
- lock contention
- throughput
- errors
- invariant violations

Never fabricate numbers.

Persist real benchmark results in:

```text
docs/benchmarks/
```

Each benchmark should record:

- machine/environment
- git commit
- configuration
- test setup
- results
- interpretation

---

# 27. CONCURRENCY EXPERIMENT

At some point compare at least two approaches where feasible.

For example:

```text
pessimistic locking

vs

optimistic locking
```

Run realistic contention tests.

Write:

```text
docs/experiments/concurrency-strategy.md
```

Discuss:

- low contention
- high contention
- retry amplification
- tail latency
- implementation complexity
- correctness reasoning

Do not change the production strategy solely because one benchmark looks faster.

Use engineering judgment.

---

# 28. CHAOS / FAILURE INJECTION

Create scripts such as:

```text
scripts/chaos/kill-sidekiq.sh

scripts/chaos/pause-kafka.sh

scripts/chaos/kill-redis.sh

scripts/chaos/restart-api.sh
```

Test scenarios:

## Kafka unavailable

Expected:

```text
authoritative bidding continues
outbox accumulates
event-driven projections become stale
recovery drains backlog
```

## Redis unavailable

Expected:

```text
authoritative auction correctness survives
some realtime/read functionality may degrade
```

## Consumer crash

Expected:

```text
restart
reprocess
duplicates tolerated
state converges
```

## Rails crash immediately after DB commit

Expected:

```text
bid persists
outbox persists
event eventually publishes
```

Document results.

---

# 29. PROPERTY / INVARIANT TESTING

Where practical, create tests asserting invariants rather than only example cases.

For example:

After arbitrary valid bid sequences:

```text
auction winner == highest valid bidder according to rules
```

After retries:

```text
number of logical bids remains correct
```

After event replay:

```text
projection converges to authoritative state
```

---

# 30. MULTI-INSTANCE TESTING

Before Kubernetes, run multiple Rails instances locally.

Example:

```text
API instance 1
API instance 2
API instance 3
```

Route concurrent bid requests across them.

Verify correctness does not depend on process-local memory.

No critical synchronization may rely on:

- Ruby mutex
- singleton process state
- local memory
- one scheduler instance

unless clearly non-authoritative.

---

# 31. SECURITY BASICS

Implement reasonable protections:

- request validation
- authentication
- authorization
- secure headers
- CSRF strategy appropriate to architecture
- rate limiting
- secret handling
- no credentials committed to Git
- safe error responses

Do not make security the dominant project theme, but avoid obviously unsafe engineering.

---

# 32. RATE LIMITING

Eventually implement bounded rate limiting for bid endpoints.

Consider:

- per user
- per IP where useful
- burst behavior
- Redis failure strategy
- preventing rate limiting from becoming auction authority

Document degradation policy.

---

# 33. DATABASE DESIGN

Take schema design seriously.

Create appropriate indexes.

Inspect query plans for important queries.

Particularly examine:

- auction fetch under bid
- bid history
- automatic-bid lookup
- outbox polling
- reconciliation queries
- closing candidate queries

Use:

```sql
EXPLAIN ANALYZE
```

where useful.

Document major performance decisions.

---

# 34. MIGRATIONS

Migrations must be:

- reversible where practical
- safe
- clear
- tested

As the system becomes more production-like, consider deploy-safe migration practices.

Avoid destructive schema changes without documentation.

---

# 35. API DESIGN

Use REST.

Possible API:

```text
GET    /api/v1/auctions
GET    /api/v1/auctions/:id

POST   /api/v1/auctions/:id/bids

PUT    /api/v1/auctions/:id/automatic-bid
DELETE /api/v1/auctions/:id/automatic-bid

GET    /api/v1/auctions/:id/bids
```

Use versioned endpoints.

Define error structures consistently.

Example:

```json
{
  "error": {
    "code": "bid_too_low",
    "message": "Bid must be at least €5,100.",
    "details": {
      "current_price": 5000,
      "minimum_bid": 5100
    }
  }
}
```

---

# 36. DOCUMENTATION

The repository must include excellent technical documentation.

Required:

```text
README.md

docs/
├── architecture.md
├── domain-model.md
├── invariants.md
├── failure-model.md
├── consistency-model.md
├── event-model.md
├── observability.md
├── running-locally.md
├── load-testing.md
├── production-readiness.md
├── security.md
│
├── adr/
│   ├── ...
│
├── experiments/
│   ├── ...
│
└── benchmarks/
    ├── ...
```

---

# 37. ADR FORMAT

Every meaningful architectural decision should use:

```text
# ADR-NNN: TITLE

## Context

## Decision

## Alternatives Considered

## Consequences

## Risks

## Revisit When
```

Important ADR candidates:

- modular monolith
- auction locking strategy
- authoritative ordering
- automatic bidding model
- auction closing semantics
- soft-close behavior
- transactional outbox
- Kafka semantics
- Redis projection model
- Sidekiq vs Kafka
- reconciliation
- WebSocket design
- Kubernetes introduction

---

# 38. README QUALITY

The README must immediately communicate that this is an engineering project.

Opening example:

> Hammerfall is a production-oriented auction platform exploring correctness and reliability under high-contention bidding.
>
> The central problem is guaranteeing one authoritative auction outcome while concurrent bidders, multiple application instances, asynchronous event consumers, caches, and real-time clients may observe or process state at different times.
>
> The project focuses on transaction semantics, bid serialization, automatic bidding, idempotency, transactional event publication, real-time projections, reconciliation, observability, load testing, and controlled failure.

Then include:

```text
Correctness guarantees
Architecture
Interesting engineering problems
Running locally
Failure scenarios
Benchmarks
Observability
ADRs
```

Do not market the project with exaggerated claims.

---

# 39. KUBERNETES

Only introduce Kubernetes after:

- local correctness is established
- Docker Compose works
- multiple API processes have been tested
- metrics exist
- health/readiness checks exist

Kubernetes deployment should include:

- API deployment
- frontend deployment
- workers
- appropriate services
- health probes
- readiness probes
- resource requests/limits
- graceful shutdown
- configuration/secrets
- horizontal scalability where appropriate

Do not run stateful infrastructure in Kubernetes merely to demonstrate YAML if managed equivalents make more sense.

---

# 40. TERRAFORM / GCP

Later create Terraform capable of provisioning a realistic deployment architecture.

Possible components:

- GKE
- Cloud SQL PostgreSQL
- Redis equivalent
- Kafka provider or appropriately justified alternative
- networking
- service accounts
- secret management
- observability integration

Do not actually incur unnecessary cloud cost.

Infrastructure code should be reviewable even if full deployment is optional.

---

# 41. CI/CD

GitHub Actions should eventually include:

```text
backend lint
backend tests

frontend lint
frontend tests

integration tests

build API image
build frontend image

optional smoke test
```

Do not make deploy credentials necessary for normal CI.

---

# 42. CODE QUALITY

Prefer:

- clear names
- explicit domain behavior
- small cohesive objects
- readable transactions
- bounded abstractions
- predictable control flow

Avoid:

- unnecessary service-object explosion
- generic repositories solely for architectural purity
- premature dependency injection
- unnecessary metaprogramming
- giant Rails callbacks
- hidden side effects
- clever Ruby that sacrifices readability

Business-critical behavior should be easy to locate.

---

# 43. RAILS DESIGN STYLE

Keep Rails idiomatic while avoiding fat-controller chaos.

Controllers should mainly:

```text
authenticate
validate request shape
invoke application/domain operation
serialize response
```

Core auction behavior should live somewhere explicit and testable.

Do not automatically create one service object per action.

Use abstractions only when they clarify the domain.

---

# 44. DATABASE AS CONCURRENCY COORDINATOR

For authoritative auction state, prefer database-backed coordination over application-local synchronization.

Assume multiple Rails instances.

Any approach must remain correct under:

```text
instance A
instance B
instance C
```

processing bids concurrently.

---

# 45. CLOCKS

Treat time as a systems problem.

Define:

- authoritative closing time
- clock source
- application clock assumptions
- test clock behavior
- scheduler delay behavior

Use UTC internally.

Frontend may display local timezone.

---

# 46. EXPERIMENTATION

Add a lightweight feature/experiment framework later.

Stable bucketing example:

```text
hash(user_id + experiment_id) % 100
```

Possible experiment:

```text
compact bidding panel
```

Track:

```text
experiment_exposed
bid_started
bid_submitted
bid_accepted
auction_won
```

Do not overbuild this.

It exists to demonstrate product-engineering thinking.

---

# 47. PRODUCTION READINESS DOCUMENT

Create:

```text
docs/production-readiness.md
```

Include:

- known bottlenecks
- capacity assumptions
- failure modes
- security concerns
- data durability
- backup assumptions
- scaling limitations
- operational runbooks
- unresolved risks
- what would need to change before handling real money

Be candid.

---

# 48. RUNBOOKS

Create small operational runbooks for:

```text
Kafka backlog growing
projection drift detected
auction close lag increasing
PostgreSQL lock contention
Redis outage
Sidekiq retries exploding
```

Each should contain:

```text
symptom
possible causes
how to investigate
safe mitigation
recovery verification
```

---

# 49. PHASED IMPLEMENTATION ROADMAP

You must implement the project in phases.

Do not build everything simultaneously.

Each phase should leave the repository working.

---

# PHASE 0 — REPOSITORY FOUNDATION

Create:

- repository structure
- README skeleton
- architecture docs skeleton
- ADR directory
- backend app
- frontend app
- Docker development foundation
- formatting/linting
- basic CI

No Kafka.

No Redis unless needed by framework tooling.

No Kubernetes.

---

# PHASE 1 — CORE AUCTION DOMAIN

Implement:

- users
- auctions
- bids
- auction state machine
- basic REST API
- PostgreSQL schema
- validation
- basic RSpec suite

Establish authoritative PostgreSQL state.

Define invariants.

---

# PHASE 2 — CORRECT CONCURRENT BIDDING

Implement:

- transactional bid placement
- authoritative bid ordering
- PostgreSQL locking strategy
- bid increments
- stale bid rejection
- concurrency tests

Run simultaneous bid tests.

Produce ADR.

---

# PHASE 3 — AUTOMATIC BIDDING

Implement:

- private max bid
- automatic bidding algorithm
- tie behavior
- concurrency behavior
- comprehensive tests

Document algorithm with examples.

---

# PHASE 4 — AUCTION CLOSING + SOFT CLOSE

Implement:

- authoritative closure
- safe close transition
- closing scheduler
- race handling
- auction extensions
- idempotent closure
- tests

Produce ADR.

---

# PHASE 5 — IDEMPOTENCY

Implement:

- Idempotency-Key
- idempotency persistence
- request fingerprinting
- concurrent duplicate handling
- tests

---

# PHASE 6 — FRONTEND

Build:

- auction listing
- auction detail
- live countdown
- bid form
- auto-bid form
- bid history
- status indicators
- responsive UI
- shadcn/ui components

Do not add fake features merely to make the UI larger.

---

# PHASE 7 — REAL-TIME UPDATES

Add:

- Action Cable
- live price updates
- bid activity
- extension events
- closed events
- reconnect handling
- stale-state reconciliation

Test disconnect/reconnect.

---

# PHASE 8 — SIDEKIQ + REDIS

Add:

- Sidekiq
- Redis
- background jobs
- notification pipeline
- scheduled reconciliation framework

Document failure semantics.

---

# PHASE 9 — TRANSACTIONAL OUTBOX

Add:

- outbox table
- outbox writes inside domain transactions
- publisher
- retries
- metrics
- tests

Simulate crash after DB commit.

---

# PHASE 10 — KAFKA

Add:

- Kafka local infrastructure
- versioned domain events
- producer
- consumer framework
- idempotent consumers
- replay behavior
- consumer failure handling

Do not migrate authoritative business logic into Kafka.

---

# PHASE 11 — REDIS PROJECTION

Build:

- event-driven auction projection
- fast reads where justified
- projection versioning
- projection freshness metadata

Ensure PostgreSQL remains authoritative.

---

# PHASE 12 — RECONCILIATION

Implement:

- drift detection
- repair
- metrics
- logs
- scheduled job
- operational visibility

Write tests that deliberately corrupt projections.

---

# PHASE 13 — OBSERVABILITY

Add:

- OpenTelemetry
- Collector
- Prometheus
- Grafana
- Tempo
- structured logging
- dashboards

Ensure trace propagation across:

```text
HTTP
Sidekiq
Kafka
```

where practical.

---

# PHASE 14 — LOAD TESTING

Add k6.

Run:

- normal load
- hot auction
- closing storm
- duplicate requests
- WebSocket load

Store results.

Investigate bottlenecks.

---

# PHASE 15 — PERFORMANCE ENGINEERING

Profile:

- DB locks
- queries
- memory
- CPU
- Rails concurrency
- connection pools

Use actual evidence.

Optimize only measured problems.

Document before/after.

---

# PHASE 16 — CHAOS TESTING

Build failure scenarios.

Verify:

- DB remains authority
- duplicate delivery safe
- event backlog recoverable
- Redis loss tolerated
- worker crashes recover
- application restart safe

Document outcomes.

---

# PHASE 17 — MULTI-INSTANCE DEPLOYMENT

Run multiple API instances locally.

Load-balance requests.

Re-run concurrency tests.

Verify no process-local assumptions exist.

---

# PHASE 18 — KUBERNETES

Create Kubernetes deployment.

Include:

- API
- frontend
- workers
- probes
- resource configuration
- scaling
- graceful termination

Run load tests against it if feasible.

---

# PHASE 19 — TERRAFORM + GCP ARCHITECTURE

Build deployable or near-deployable infrastructure definitions.

Document estimated architecture and costs.

Do not create unnecessary paid resources without explicit instruction.

---

# PHASE 20 — FINAL ENGINEERING POLISH

Perform full repository review.

Improve:

- code quality
- architecture docs
- README
- ADRs
- dashboards
- tests
- runbooks
- benchmarks
- diagrams

Remove dead code.

Remove experimental junk.

Ensure naming consistency.

---

# 50. AGENT WORKING MODE

You are allowed to implement the product autonomously.

You should:

- create files
- modify files
- run commands
- install dependencies
- run tests
- inspect failures
- debug failures
- refactor
- build Docker images
- run local services
- execute load tests
- update documentation

Do not require the user to manually write implementation code.

However, maintain engineering discipline.

---

# 51. DO NOT ASK UNNECESSARY QUESTIONS

When a reasonable engineering default exists, choose it and document it.

Ask only when:

- a decision has substantial irreversible consequences
- external credentials are required
- real cloud expenditure would occur
- destructive operations would affect user-owned data
- legal/product semantics genuinely require user input

Otherwise proceed.

---

# 52. NEVER HIDE PROBLEMS

If something fails:

1. diagnose it
2. explain the root cause in project notes where relevant
3. fix it
4. rerun verification

Never silently disable tests.

Never delete failing tests merely to get green CI.

Never weaken an invariant because implementation is difficult.

---

# 53. NEVER FAKE RESULTS

Do not fabricate:

- performance numbers
- benchmark results
- test output
- operational claims
- scalability claims

If a test has not actually been run, say so.

If infrastructure cannot be executed locally, clearly label it unverified.

---

# 54. ARCHITECTURAL CHANGE RULE

Before significant architectural changes:

1. identify the problem
2. identify alternatives
3. choose an approach
4. document it as an ADR when substantial
5. implement
6. test
7. update architecture documentation

Do not introduce technology merely because it is listed in this prompt.

Technology must solve an actual project problem.

---

# 55. TESTING RULE

Every meaningful feature requires appropriate tests.

Especially:

- concurrency
- idempotency
- automatic bidding
- closure
- event delivery
- reconciliation

Avoid mostly-mocked tests for distributed behavior.

Where feasible use real:

- PostgreSQL
- Redis
- Kafka

for integration testing.

---

# 56. DEFINITION OF DONE FOR EACH PHASE

A phase is complete only when:

- implementation works
- tests pass
- lint passes
- relevant integration test passes
- docs are updated
- important design decisions are recorded
- Docker/local setup still works
- no known serious correctness bug remains

Record phase completion in:

```text
docs/progress.md
```

Use:

```text
## Phase N — Name

Status: COMPLETE

Implemented:
...

Tests:
...

Design decisions:
...

Known limitations:
...

Next phase:
...
```

---

# 57. LEARNING DOCUMENT

Because the owner intends to study the finished system afterward, maintain:

```text
docs/learning-guide.md
```

For every major subsystem explain:

## What problem existed?

## What naive implementation would look like?

## Why would that implementation fail?

## What implementation was chosen?

## What guarantees does it provide?

## What guarantees does it NOT provide?

## Which files should be read first?

## Which tests best demonstrate the behavior?

## What should an engineer be able to explain in an interview?

Cover at least:

- bid serialization
- automatic bidding
- idempotency
- auction closing
- soft-close
- outbox
- Kafka
- consumer idempotency
- Redis projections
- reconciliation
- WebSockets
- observability
- load testing
- Kubernetes

This file is extremely important.

---

# 58. CODE WALKTHROUGH MAP

Maintain:

```text
docs/code-map.md
```

Example:

```text
Placing a bid

HTTP entry:
apps/api/app/controllers/...

Application operation:
...

Transaction:
...

Domain logic:
...

Persistence:
...

Outbox:
...

Realtime publication:
...

Tests:
...
```

Provide maps for the most important workflows.

This is intended to let the owner learn the codebase efficiently after implementation.

---

# 59. INTERVIEW PREPARATION DOCUMENT

At the end create:

```text
docs/interview-guide.md
```

Include questions such as:

```text
Why PostgreSQL as authority?

Why not Kafka as authority?

Why pessimistic/optimistic locking?

How do you prevent duplicate bids?

What happens when Kafka is unavailable?

What happens when Redis loses everything?

How does automatic bidding work?

What happens when two users choose the same maximum?

How do auctions close safely across multiple Rails instances?

What happens if a worker crashes after processing a Kafka message but before committing its offset?

How does reconciliation work?

What does eventual consistency mean in this system?

What does at-least-once delivery mean here?

What are the project's scaling bottlenecks?

What would you change at 100x traffic?
```

Provide concise answers referencing actual implementation files.

---

# 60. ENGINEERING JOURNAL

Maintain:

```text
docs/engineering-journal.md
```

Record meaningful discoveries during implementation:

- surprising Ruby/Rails behavior
- PostgreSQL locking observations
- race conditions discovered
- Kafka behavior
- WebSocket issues
- load-test bottlenecks
- mistakes made
- architecture changes

Do not log trivial work.

This should read like an engineering diary.

---

# 61. FINAL SYSTEM REVIEW

At project completion perform a complete adversarial review.

Inspect:

- correctness
- security
- concurrency
- failure handling
- tests
- architecture
- operational readiness
- performance
- documentation

Create:

```text
docs/final-review.md
```

Categorize findings:

```text
Critical
High
Medium
Low
Future work
```

Fix all Critical and High issues that are reasonably fixable.

---

# 62. FINAL DELIVERABLE

The final repository should demonstrate:

```text
Ruby/Rails engineering
TypeScript/React engineering
PostgreSQL transactional reasoning
concurrency control
automatic bidding
idempotency
WebSockets
Redis
Sidekiq
Kafka
transactional outbox
event-driven architecture
eventual consistency
reconciliation
OpenTelemetry
Prometheus
Grafana
distributed tracing
load testing
failure injection
multi-instance correctness
Docker
Kubernetes
Terraform
CI/CD
architecture documentation
production reasoning
```

But technical breadth is secondary to correctness.

---

# 63. WHAT SUCCESS LOOKS LIKE

Someone inspecting the repository should be able to conclude:

> This engineer did not merely build an auction CRUD application.

They should see:

- explicit invariants
- careful transaction boundaries
- realistic race-condition handling
- evidence-based performance work
- reliable event publication
- safe duplicate handling
- observable distributed behavior
- recovery from stale state
- clear architectural decisions
- operational thinking
- honest limitations

---

# 64. STARTING INSTRUCTION

Begin with Phase 0.

Before writing implementation code:

1. inspect the repository
2. establish the project structure
3. create `docs/progress.md`
4. create `docs/architecture.md`
5. create `docs/domain-model.md`
6. create `docs/invariants.md`
7. create `docs/learning-guide.md`
8. create `docs/code-map.md`
9. create the first ADR explaining the modular-monolith starting architecture

Then scaffold the backend and frontend.

Proceed autonomously through the roadmap.

Do not skip phases.

Do not introduce technologies earlier than necessary.

At the end of every phase:

- run tests
- run linting
- update documentation
- update `docs/progress.md`
- commit logically coherent changes if Git operations are available

Continue to the next phase unless blocked by something requiring user credentials, money, destructive access, or a truly product-defining decision.

Your objective is not merely to finish Hammerfall.

Your objective is to leave behind a codebase whose architecture, tests, documentation, experiments, and failure behavior teach the owner how a serious distributed auction system works.