# Phase 15 — Performance Engineering

Status: Complete — 2026-10-02. See the [final performance review](../benchmarks/phase-15-final.md)
and [verification index](../benchmarks/phase-15-final-gates/README.md).

## Goal

Deliver the roadmap's performance engineering scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 14 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [operations-and-security](../architecture/operations-and-security.md), [auction-state](../architecture/auction-state.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Profile:

- DB locks
- queries
- memory
- CPU
- Rails concurrency
- connection pools

Use actual evidence.

Optimize only measured problems.

Document before/after.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Profile locks, queries, memory, CPU, Rails concurrency and pools; record before/after evidence for each optimization. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not change concurrency strategy solely because one benchmark is faster. Do not start Phase 16 without an explicit request.
