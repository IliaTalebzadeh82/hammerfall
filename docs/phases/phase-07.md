# Phase 07 — Real-Time Updates

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's real-time updates scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 06 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [realtime-and-frontend](../architecture/realtime-and-frontend.md), [auction-state](../architecture/auction-state.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Add:

- Action Cable
- live price updates
- bid activity
- extension events
- closed events
- reconnect handling
- stale-state reconciliation

Test disconnect/reconnect.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test cross-process notification, reconnect/missed hint recovery, revision ordering, rollback silence, private-only silence and browser behavior. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not treat Cable hints as durable events, bids, outcomes or snapshots. Do not start Phase 08 without an explicit request.
