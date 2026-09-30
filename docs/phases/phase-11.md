# Phase 11 — Redis Projection

Status: Complete — verified 2026-09-30; see the [ExecPlan](../plans/phase-11-execplan.md)

## Goal

Deliver the roadmap's redis projection scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 10 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [projections-and-reconciliation](../architecture/projections-and-reconciliation.md), [async-events](../architecture/async-events.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Build:

- event-driven auction projection
- fast reads where justified
- projection versioning
- projection freshness metadata

Ensure PostgreSQL remains authoritative.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test version/freshness, duplicate and out-of-order events, Redis loss, stale reads and recovery against PostgreSQL. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not allow Redis to decide bid acceptance, price, deadline or winner. Do not start Phase 12 without an explicit request.
