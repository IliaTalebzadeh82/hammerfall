# Phase 10 — Kafka

Status: Complete — 2026-09-30. Implementation, real Kafka failure/replay,
sabotage, regression and limits are recorded in [the ExecPlan](../plans/phase-10-execplan.md)
and [progress](../progress.md). Phase 11 has not begun.

## Goal

Deliver the roadmap's kafka scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 09 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [async-events](../architecture/async-events.md), [projections-and-reconciliation](../architecture/projections-and-reconciliation.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Add:

- Kafka local infrastructure
- versioned domain events
- producer
- consumer framework
- idempotent consumers
- replay behavior
- consumer failure handling

Do not migrate authoritative business logic into Kafka.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test schema versions, producer/consumer retry, duplicates, poison records, ordering, restart and replay with real Kafka where feasible. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not claim exactly-once delivery without proof or move auction authority to Kafka. Do not start Phase 11 without an explicit request.
