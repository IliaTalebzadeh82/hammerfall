# Phase 12 — Reconciliation

Status: Complete — 2026-10-01. See the [ExecPlan](../plans/phase-12-execplan.md)
and [progress](../progress.md) for actual verification and limits. Phase 13
requires a separate explicit request.

## Goal

Deliver the roadmap's reconciliation scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 11 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [projections-and-reconciliation](../architecture/projections-and-reconciliation.md), [operations-and-security](../architecture/operations-and-security.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Implement:

- drift detection
- repair
- metrics
- logs
- scheduled job
- operational visibility

Write tests that deliberately corrupt projections.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

The checker should report `auction_projection_drift_total`,
`auction_projection_repair_total` and
`auction_projection_repair_failure_total` (or clearly documented equivalent
metrics). Specify compared fields, automatic versus operator repair, idempotency,
structured repair logs and deliberate corruption tests.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Deliberately corrupt projections; verify drift detection, safe idempotent repair, failure metrics/logging and operator escalation. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not silently auto-repair ambiguous authoritative defects. Do not start Phase 13 without an explicit request.
