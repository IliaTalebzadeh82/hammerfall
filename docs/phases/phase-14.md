# Phase 14 — Load Testing

Status: Complete — 2026-10-01. The [ExecPlan](../plans/phase-14-execplan.md),
[final evidence review](../benchmarks/phase-14-final.md) and
[progress](../progress.md) record actual verification and limits. Phase 15
requires a separate explicit request.

## Goal

Deliver the roadmap's load testing scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 13 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [operations-and-security](../architecture/operations-and-security.md), [auction-state](../architecture/auction-state.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Add k6.

Run:

- normal load
- hot auction
- closing storm
- duplicate requests
- WebSocket load

Store results.

Investigate bottlenecks.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Run and record real k6 scenarios including hot auction, closing storm, duplicate retries and socket fanout; check invariants and p50/p95/p99. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not fabricate benchmark data or infer capacity from a smoke test. Do not start Phase 15 without an explicit request.
