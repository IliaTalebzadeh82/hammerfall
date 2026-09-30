# Phase 20 — Final Engineering Polish

Status: Planned; begin only on an explicit request

## Goal

Deliver the roadmap's final engineering polish scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 19 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [system-boundaries](../architecture/system-boundaries.md), [operations-and-security](../architecture/operations-and-security.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Perform full repository review.

Improve:

- code quality
- architecture docs
- README
- ADRs
- dashboards
- tests
- runbooks
- benchmarks
- diagrams

Remove dead code.

Remove experimental junk.

Ensure naming consistency.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Run full regression and an adversarial review; resolve reasonably fixable critical/high findings and reconcile docs with code. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not claim readiness or final guarantees that evidence does not support. Do not add unrequested post-roadmap work.
