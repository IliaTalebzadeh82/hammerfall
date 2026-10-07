# Phase 24 — Final Engineering Polish

Status: IN PROGRESS — explicitly authorized 2026-10-07

## Goal

Deliver the original Phase 20 Final Engineering Polish scope as the last phase of the extended roadmap. Preserve PostgreSQL auction authority and a working repository. Polish the Catawiki-aligned engineering case study without claiming knowledge of Catawiki's internal architecture.

## Prerequisites

Phases 20–23 completed and verified; review the latest handoff and Phase 23 case-study deliverables. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [system-boundaries](../architecture/system-boundaries.md), [operations-and-security](../architecture/operations-and-security.md). Review applicable ADRs and implementation before changing an established contract.

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

A technically experienced engineer unfamiliar with Hammerfall can understand why the project exists, its principal architecture, its strongest engineering evidence, and its important limitations without reading the full development history.

## Out of scope

Do not claim readiness or final guarantees that evidence does not support. Phase 24 ends the Hammerfall engineering roadmap. After it, stop building Hammerfall unless a concrete future learning need or Catawiki conversation reveals a specific meaningful gap. Do not add Phase 25+ placeholders.
