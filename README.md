# Hammerfall

Hammerfall is an auction engineering project exploring correctness under
high-contention bidding. Its central question is how to guarantee one authoritative
outcome while concurrent requests, application instances, asynchronous consumers,
and real-time clients may observe different versions of state.

**Current scope: Phase 0 — repository foundation.** There is no auction domain or
auction interface yet. [masterprompt.md](masterprompt.md) is the authoritative
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

No auction correctness guarantee is implemented yet. The [invariants](docs/invariants.md)
remain explicit requirements. Rails will own authoritative business logic;
PostgreSQL will own authoritative state. Next.js handles presentation.
See [architecture](docs/architecture.md), [domain model](docs/domain-model.md), and
[ADR-001](docs/adr/001-modular-monolith.md) for the modular-monolith decision.

The roadmap investigates bid serialization, automatic bidding, closing races,
idempotency, event delivery, and reconciliation in that order. It does not claim
these problems are already solved.

## Verification and learning

After native dependencies are installed and PostgreSQL is running:

```sh
./scripts/check
```

CI checks Ruby lint/security/tests, frontend lint/format/types/tests/build, and
Compose startup. [Version choices](docs/tooling.md), [code map](docs/code-map.md),
and [learning guide](docs/learning-guide.md) explain the foundation.

## Later engineering work

[Failure scenarios](docs/failure-model.md), [consistency](docs/consistency-model.md),
[event contracts](docs/event-model.md), [benchmarks](docs/load-testing.md), and
[observability](docs/observability.md) are planning notes. No benchmark results,
event pipeline, or dashboards exist yet. See [security](docs/security.md) and
[production readiness](docs/production-readiness.md) for current limits.
