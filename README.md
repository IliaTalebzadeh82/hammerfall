# Hammerfall

Hammerfall is an auction engineering project exploring correctness under
high-contention bidding. Its central question is how to guarantee one authoritative
outcome while concurrent requests, application instances, asynchronous consumers,
and real-time clients may observe different versions of state.

**Current scope: Phase 12 — Reconciliation.** Browse real auctions, inspect public bid
history, select an explicit demo bidder, and submit manual or private maximum bids.
The responsive Next.js interface preserves stable client intentions for safe retry
after lost responses, including tab reload. Rails/PostgreSQL still owns price,
leader, deadline extensions and final winner. Auction details receive PostgreSQL-backed
Action Cable invalidations, dispatched through a PostgreSQL outbox and Sidekiq,
and recover current state through REST on confirmation/reconnect. The outbox
preserves committed publication intent across API crash and Redis outage. A
separate Kafka publisher carries public domain events from the same committed
outbox to an idempotent audit consumer and a separate public Redis projection
consumer. The explicit eventual public-state endpoint can use Redis or fall
back to PostgreSQL. A scheduled checker compares Redis with authoritative
PostgreSQL public state and safely repairs missing or older projections;
ambiguous state needs operator review. Bounded PostgreSQL leases prevent
scheduled scan overlap. Kafka, Redis and scheduler state do not decide auction outcomes;
[realtime](docs/realtime.md) documents the remaining delivery limits. Start future work with
[AGENTS.md](AGENTS.md), the [latest handoff](docs/handoffs/latest.md), the relevant
[phase specification](docs/phases/), and the [context map](docs/context-map.md).
[Progress](docs/progress.md) records actual verification; the original master prompt
is [archived for audit](docs/archive/masterprompt-original.md).

## Run locally

With Docker Engine and Compose installed:

```sh
cp .env.example .env
docker compose up --build --wait
```

Open [the frontend](http://localhost:3000). Rails liveness is at
[localhost:3001/up](http://localhost:3001/up). First startup downloads dependencies.
See [running locally](docs/running-locally.md) for native development, verification,
port overrides, dependency updates, and shutdown.

## Repository

- `apps/api`: Rails API, ActiveRecord/PostgreSQL, RSpec, RuboCop, Brakeman.
- `apps/web`: Next.js App Router, TypeScript, Tailwind, shadcn/ui, Vitest.
- `infrastructure`: development Dockerfiles; root Compose coordinates PostgreSQL,
  Redis, Kafka, API, web, Sidekiq, two outbox publishers, Kafka audit and projection consumers,
  reconciliation scheduler and auction closer.
- `scripts`: shared local verification.
- `docs`: architecture, decisions, learning notes, and progress.
- `load-tests`, `observability`: documented future locations; no tooling installed.

## Correctness and architecture

The [invariants](docs/invariants.md) distinguish implemented concurrency guarantees
from future event-delivery requirements. Rails owns business logic and
PostgreSQL owns persisted state. Money uses integer EUR cents. Bid insertion and
current-price update are atomic; explicit close assigns the winner. [ADR-003](docs/adr/003-auction-concurrency-control.md) explains serialization and
the hot-auction bottleneck. Next.js presents public GET state and never optimistically decides price or leader.
See [frontend](docs/frontend.md), [architecture](docs/architecture.md), [domain model](docs/domain-model.md), and
[ADR-001](docs/adr/001-modular-monolith.md) for the modular-monolith decision.

The remaining roadmap starts with later operations work. The current API has no authentication; bidder
IDs are demo identity only. See [API usage](docs/api.md) and
[ADR-002](docs/adr/002-core-auction-state.md) for the domain choices.

## Verification and learning

After native dependencies are installed and PostgreSQL is running:

```sh
./scripts/check
```

CI checks Ruby lint/security/tests, frontend lint/format/types/tests/build, and
Compose startup, HTTP smoke tests and real-API Playwright browser scenarios. [Version choices](docs/tooling.md), [code map](docs/code-map.md),
and [learning guide](docs/learning-guide.md) explain the foundation.

## Later engineering work

[Failure scenarios](docs/failure-model.md), [job/Redis runbook](docs/runbooks/sidekiq-redis.md), [Kafka runbook](docs/runbooks/kafka.md), [projection recovery](docs/runbooks/redis-projection.md), [reconciliation operations](docs/runbooks/projection-reconciliation.md), [consistency](docs/consistency-model.md),
[event contracts](docs/event-model.md), [benchmarks](docs/load-testing.md), and
[observability](docs/observability.md) describe current limits and future work. No
benchmark results or dashboards exist yet. See [security](docs/security.md) and
[production readiness](docs/production-readiness.md) for current limits.
