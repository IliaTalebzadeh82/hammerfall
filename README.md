# Hammerfall

Hammerfall is an auction engineering project exploring correctness under
high-contention bidding. Its central question is how to guarantee one authoritative
outcome while concurrent requests, application instances, asynchronous consumers,
and real-time clients may observe different versions of state.

**Current scope: Phase 2 — correct concurrent bidding.** PostgreSQL auction row
locks serialize fresh validation, bid sequence assignment and atomic price/history
writes across Rails processes. The real auction frontend is not implemented. [masterprompt.md](masterprompt.md) is the authoritative
engineering specification; [progress](docs/progress.md) records verified work.

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
- `infrastructure`: development Dockerfiles; root Compose coordinates services.
- `scripts`: shared local verification.
- `docs`: architecture, decisions, learning notes, and progress.
- `load-tests`, `observability`: documented future locations; no tooling installed.

## Correctness and architecture

The [invariants](docs/invariants.md) distinguish implemented concurrency guarantees
from future closing/delivery requirements. Rails owns business logic and
PostgreSQL owns persisted state. Money uses integer EUR cents. Bid insertion and
current-price update are atomic; explicit close assigns the winner. [ADR-003](docs/adr/003-auction-concurrency-control.md) explains serialization and
the hot-auction bottleneck. Next.js still serves the original starting page.
See [architecture](docs/architecture.md), [domain model](docs/domain-model.md), and
[ADR-001](docs/adr/001-modular-monolith.md) for the modular-monolith decision.

The remaining roadmap investigates automatic bidding, distributed closing,
idempotency, event delivery, and reconciliation in that order. It does not claim
these problems are already solved. The current API has no authentication; bidder
IDs are demo identity only. See [API usage](docs/api.md) and
[ADR-002](docs/adr/002-core-auction-state.md) for the domain choices.

## Verification and learning

After native dependencies are installed and PostgreSQL is running:

```sh
./scripts/check
```

CI checks Ruby lint/security/tests, frontend lint/format/types/tests/build, and
Compose startup plus sequential and concurrent HTTP auction smoke tests. [Version choices](docs/tooling.md), [code map](docs/code-map.md),
and [learning guide](docs/learning-guide.md) explain the foundation.

## Later engineering work

[Failure scenarios](docs/failure-model.md), [consistency](docs/consistency-model.md),
[event contracts](docs/event-model.md), [benchmarks](docs/load-testing.md), and
[observability](docs/observability.md) are planning notes. No benchmark results,
event pipeline, or dashboards exist yet. See [security](docs/security.md) and
[production readiness](docs/production-readiness.md) for current limits.
