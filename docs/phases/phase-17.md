# Phase 17 — Multi-Instance Deployment

Status: Planned; begin only on an explicit request

## Goal

Deliver the roadmap's multi-instance deployment scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 16 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [auction-state](../architecture/auction-state.md), [deadlines](../architecture/deadlines.md), [idempotency](../architecture/idempotency.md), [realtime-and-frontend](../architecture/realtime-and-frontend.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Run multiple API instances locally.

Load-balance requests.

Re-run concurrency tests.

Verify no process-local assumptions exist.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Load-balance multiple local API instances and rerun concurrency, retry, closing and realtime recovery tests. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not assume one process or scheduler is the correctness boundary. Do not start Phase 18 without an explicit request.
