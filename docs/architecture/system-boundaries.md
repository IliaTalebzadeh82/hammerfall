# System boundaries and evolution

## Purpose

Hammerfall tests how one correct auction outcome survives concurrent bids, asynchronous work and stale clients. It is a Catawiki-aligned engineering case study, informed by public product and technology information, for learning the difficult auction-marketplace problems and discussing evidence and trade-offs with Catawiki engineers. It is not a claim about their internal architecture or a complete marketplace clone. Keep the product narrow: browse and inspect auctions/history, bid or set a private maximum, see countdowns/extensions and final outcomes. A disabled-by-default internal operator API provides bounded auction/projection diagnosis and reconciliation; runbooks cover deeper recovery. Seller onboarding, shipping, messaging, reviews, recommendations, elaborate profiles, social features, complex payments and catalog systems are outside this focus.

## Current responsibilities

Rails/ActiveRecord is the modular monolith and sole business authority. PostgreSQL persists users, auctions, bids, private maxima, winner and idempotency outcomes. Next.js/React/TypeScript presents the versioned REST API and ephemeral Action Cable invalidations. Compose runs PostgreSQL, Redis, Kafka, API, web, Sidekiq, independent Sidekiq/Kafka outbox publishers, a Kafka audit consumer, a read-only sweep scheduler and a separate Rails closer. See [ADR-001](../adr/001-modular-monolith.md), [ADR-011](../adr/011-kafka-domain-events.md), [architecture](../architecture.md) and [code map](../code-map.md).

## Durable boundary

- Do not move authoritative auction logic to Node, Go or a client. A cached or event-derived state never decides the winner.
- Start with one Rails app. Extract a service only for a concrete independent scaling, availability, deployment, workload, ownership or fault-isolation reason, recorded in an ADR.
- Phase 8 added Redis/Sidekiq jobs, Phase 9 the PostgreSQL outbox, and Phase 10 Kafka domain event propagation and an audit consumer. Kafka and Sidekiq have different responsibilities. Neither decides an auction result.
- Keep the application usable and documented after every phase; do not introduce Kubernetes before local correctness, Compose, multi-instance tests, metrics and readiness evidence.

## Technology and documentation contracts

The stack includes Ruby/Rails API, ActiveRecord, PostgreSQL, RSpec; TypeScript, React, Next.js, Tailwind and shadcn/ui; Action Cable/WebSockets; Redis, Sidekiq and Kafka. Phase 18 verified local Kubernetes orchestration of application processes under [ADR-014](../adr/014-local-kubernetes-process-orchestration.md); Phase 19 completed a default-disabled Terraform/GCP reference without a paid deployment. A change needs a reason and ADR. Docker Compose remains the local stateful dependency foundation; GitHub Actions runs ordinary checks without deployment credentials. [README](../../README.md), [tooling](../tooling.md), [running locally](../running-locally.md) and [production readiness](../production-readiness.md) distinguish installed from future tools.

Maintain ADRs with Context, Decision, Alternatives Considered, Consequences, Risks and Revisit When. The learning guide, workflow code map, substantive engineering journal, candid production readiness and final interview/review documents serve the owner's study goal. Do not exaggerate completion in README or operational claims.

The numbered ADRs cover Redis projection, reconciliation, local Kubernetes
process orchestration, modularity, locking, proxy bidding, deadline/soft close,
idempotency, browser intentions and realtime invalidation.
