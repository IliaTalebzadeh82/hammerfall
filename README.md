# Hammerfall

Hammerfall is an auction engineering project exploring correctness under
high-contention bidding. Its central question is how to guarantee one authoritative
outcome while concurrent requests, application instances, asynchronous consumers,
and real-time clients may observe different versions of state.

**Completed through Phase 20; Phase 21 has not started.**
Phase 20 adds authenticated first-party identities, authorization, seller self-bid
protection, bounded request and rate controls, versioned keyed idempotency digests,
authenticated realtime admission and verified multi-instance behavior while retaining
PostgreSQL auction authority. Phase 18 verified local Kubernetes orchestration, and Phase 19 added a
default-disabled Terraform/GCP reference without cloud deployment. See
[local Kubernetes setup](k8s/README.md) and the [latest handoff](docs/handoffs/latest.md)
for their scope and limits.

Browse real auctions, inspect public bid
history, sign in with a local demo identity, and submit manual or private maximum bids.
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
scheduled scan overlap. Kafka, Redis and scheduler state do not decide auction outcomes.
OpenTelemetry carries bounded trace context across HTTP, Sidekiq and Kafka.
An optional local Collector, Prometheus, Tempo and Grafana stack exposes
metrics, distributed traces and an operations dashboard; Rails emits structured
boundary logs. Telemetry loss does not decide auction outcomes. See the
[observability contract](docs/observability.md) and
[runbook](docs/runbooks/observability.md) for signal limits and local inspection.
[ADR-010](docs/adr/010-transactional-public-outbox.md) and
[ADR-011](docs/adr/011-kafka-domain-events.md) document the retained publisher
row locks across external delivery and their unmeasured scaling cost. The API
has a 32 KiB pre-parse body guard and versioned HMAC digests for new idempotency
claims; [security](docs/security.md) describes the guarantees and accepted limits.
It is not a public production service.
[Realtime](docs/realtime.md) documents the remaining delivery limits. Start future work with
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
Port 3001 reaches a local proxy that balances two Rails API containers.
See [running locally](docs/running-locally.md) for native development, verification,
port overrides, dependency updates, and shutdown.

## Repository

- `apps/api`: Rails API, ActiveRecord/PostgreSQL, RSpec, RuboCop, Brakeman.
- `apps/web`: Next.js App Router, TypeScript, Tailwind, shadcn/ui, Vitest.
- `infrastructure`: development Dockerfiles and local API proxy; root Compose coordinates PostgreSQL,
  Redis, Kafka, two API instances, web, Sidekiq, two outbox publishers, Kafka audit and projection consumers,
  reconciliation scheduler and auction closer.
- `scripts`: shared local verification.
- `docs`: architecture, decisions, learning notes, and progress.
- `infrastructure/observability`: optional local Collector, Prometheus, Tempo
  and provisioned Grafana dashboard.
- `load-tests`: pinned k6 scenarios, environment capture and authoritative
  PostgreSQL post-run verification. See the [local benchmark evidence](docs/benchmarks/README.md).

## Correctness and architecture

The [invariants](docs/invariants.md) distinguish implemented concurrency guarantees
from future event-delivery requirements. Rails owns business logic and
PostgreSQL owns persisted state. Money uses integer EUR cents. Bid insertion and
current-price update are atomic; explicit close assigns the winner. [ADR-003](docs/adr/003-auction-concurrency-control.md) explains serialization and
the hot-auction bottleneck. Next.js presents public GET state and never optimistically decides price or leader.
See [frontend](docs/frontend.md), [architecture](docs/architecture.md), [domain model](docs/domain-model.md), and
[ADR-001](docs/adr/001-modular-monolith.md) for the modular-monolith decision.

Phase 20's boundary and evidence are in the [final review](docs/security/phase-20-final.md).
See [API usage](docs/api.md) and
[ADR-002](docs/adr/002-core-auction-state.md) for the domain choices.

## Verification and learning

After native dependencies are installed and PostgreSQL is running:

```sh
./scripts/check
```

CI checks Ruby lint/security/tests, frontend lint/format/types/tests/build, and
Compose startup, HTTP smoke tests and real-API Playwright browser scenarios. [Version choices](docs/tooling.md), [code map](docs/code-map.md),
and [learning guide](docs/learning-guide.md) explain the foundation.

## Cloud reference

[Phase 19's Terraform/GCP reference](docs/cloud/phase-19-final.md) defines a
gated GKE Autopilot, Cloud SQL, Redis and managed Kafka topology with a GKE
workload overlay, managed-service client contracts and a [cost model](docs/cloud/cost-estimate.md).
It is locally and statically validated; no live GCP deployment or managed-service
connection has been performed.

## Later engineering work

[Failure scenarios](docs/failure-model.md), [job/Redis runbook](docs/runbooks/sidekiq-redis.md), [Kafka runbook](docs/runbooks/kafka.md), [projection recovery](docs/runbooks/redis-projection.md), [reconciliation operations](docs/runbooks/projection-reconciliation.md), [consistency](docs/consistency-model.md),
[event contracts](docs/event-model.md), [benchmarks](docs/load-testing.md), and
[observability](docs/observability.md) describe current limits and future work. The
local benchmark results are comparative evidence, not production capacity. See [security](docs/security.md) and
[production readiness](docs/production-readiness.md) for current limits.
