# System boundaries and evolution

## Purpose

Hammerfall tests how one correct auction outcome survives concurrent bids, asynchronous work and stale clients. Keep the product narrow: browse and inspect auctions/history, bid or set a private maximum, see countdowns/extensions and final outcomes. A minimal operator surface should eventually expose auction/bid state, reconciliation, failed processing and degraded health. Seller onboarding, shipping, messaging, reviews, recommendations, elaborate profiles, social features, complex payments and catalog systems are outside this focus unless justified later.

## Current responsibilities

Rails/ActiveRecord is the modular monolith and sole business authority. PostgreSQL persists users, auctions, bids, private maxima, winner and idempotency outcomes. Next.js/React/TypeScript presents the versioned REST API and ephemeral Action Cable invalidations. Compose currently runs PostgreSQL, API, web and a separate Rails closer role. See [ADR-001](../adr/001-modular-monolith.md), [architecture](../architecture.md) and [code map](../code-map.md).

## Durable boundary

- Do not move authoritative auction logic to Node, Go or a client. A cached or event-derived state never decides the winner.
- Start with one Rails app. Extract a service only for a concrete independent scaling, availability, deployment, workload, ownership or fault-isolation reason, recorded in an ADR.
- A future system may add Redis/Sidekiq, PostgreSQL outbox, Kafka and derived consumers in that order. They are not present merely because the roadmap names them. Kafka and Sidekiq have different responsibilities: domain event propagation versus application jobs.
- Keep the application usable and documented after every phase; do not introduce Kubernetes before local correctness, Compose, multi-instance tests, metrics and readiness evidence.

## Technology and documentation contracts

The planned stack is Ruby/Rails API, ActiveRecord, PostgreSQL and RSpec; TypeScript, React, Next.js, Tailwind and shadcn/ui; Action Cable/WebSockets; later Redis, Sidekiq, Kafka, OpenTelemetry/Collector, Prometheus, Grafana, Tempo, k6, Kubernetes, Terraform and GCP. A change needs a reason and ADR. Docker Compose is the local foundation; GitHub Actions runs ordinary checks without deployment credentials. [README](../../README.md), [tooling](../tooling.md), [running locally](../running-locally.md) and [production readiness](../production-readiness.md) distinguish installed from future tools.

Maintain ADRs with Context, Decision, Alternatives Considered, Consequences, Risks and Revisit When. The learning guide, workflow code map, substantive engineering journal, candid production readiness and final interview/review documents serve the owner's study goal. Do not exaggerate completion in README or operational claims.

Potential future ADRs should cover authoritative ordering, outbox, Kafka delivery,
Redis projection, Sidekiq versus Kafka, reconciliation and Kubernetes when those
decisions become concrete. The current numbered ADRs already cover modularity,
locking, proxy bidding, deadline/soft close, idempotency, browser intentions and
realtime invalidation.
