# ADR-001: Begin with a modular Rails monolith

Status: Accepted — Phase 0, 2026-09-23

## Context

Hammerfall must eventually serialize bids and auction closure correctly under
contention. The first engineering problem is establishing a clear transactional
authority, not distributing unfinished business logic across services.

## Decision

Use one idiomatic Rails application for authoritative business operations and
PostgreSQL persistence. Use a separate Next.js application for presentation.
Keep conceptual domain boundaries explicit as behavior appears; do not create
empty modules or a generic abstraction layer in Phase 0.

## Alternatives Considered

- Microservices immediately: introduce network failure, distributed transactions,
  event contracts, and deployment coordination before identifying stable boundaries.
- Rails-only presentation: simpler deployment, but does not meet the specified
  Next.js/React frontend stack and future client interaction requirements.
- Generic domain framework inside Rails: adds indirection without current behavior
  that justifies it.

## Consequences

One database transaction can eventually protect bid and auction state together.
The domain is easier to test and inspect. Rails code must remain cohesive as it
grows. Separate frontend deployment does not make the backend a microservice system.

## Risks

Shared deployment and database resources can become scaling or ownership limits.
A monolith can still become tightly coupled if boundaries are neglected. Neither
this architecture nor Rails alone guarantees correct concurrent bidding.

## Revisit When

Measured independent scaling, availability, fault isolation, deployment lifecycle,
workload, or team ownership needs justify extraction. Record a new ADR and preserve
authoritative invariants before introducing a service boundary.
