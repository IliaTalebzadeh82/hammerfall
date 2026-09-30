# Phase 08 — Sidekiq + Redis

Status: Planned; begin only on an explicit request

## Goal

Deliver the roadmap's sidekiq + redis scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 07 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [async-events](../architecture/async-events.md), [realtime-and-frontend](../architecture/realtime-and-frontend.md), [operations-and-security](../architecture/operations-and-security.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Add:

- Sidekiq
- Redis
- background jobs
- notification pipeline
- scheduled reconciliation framework

Document failure semantics.

The Phase 7 handoff adds current constraints: preserve synchronous PostgreSQL bid,
price, deadline and winner authority; public revision and after-commit privacy;
stable ambiguous browser intentions and REST reconnect recovery. Define job
idempotency, bounded retries, duplicate/delayed/reordered/lost work, worker and
Redis outage degradation, operator recovery and notification privacy. A scheduled
reconciliation **framework** can be introduced here; actual Redis projection drift
comparison and repair belong to Phase 12 after Phase 11 supplies a projection.
If the Action Cable adapter changes, prove cross-process behavior with real
independent Rails instances and document its new failure semantics.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test duplicate/retried/delayed jobs, Redis/worker outage and recovery, notification privacy, scheduled reconciliation scaffolding and unaffected authoritative bidding. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not add Phase 9 outbox or Phase 10 Kafka early; a job queue alone does not close the commit/enqueue crash gap. Do not start Phase 09 without an explicit request.
