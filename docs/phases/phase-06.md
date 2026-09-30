# Phase 06 — Frontend

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's frontend scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 05 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [realtime-and-frontend](../architecture/realtime-and-frontend.md), [idempotency](../architecture/idempotency.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Build:

- auction listing
- auction detail
- live countdown
- bid form
- auto-bid form
- bid history
- status indicators
- responsive UI
- shadcn/ui components

Do not add fake features merely to make the UI larger.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test real API forms/history, mobile and desktop layouts, safe retry after response loss, stale errors, public-field privacy and countdown refresh. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not add fake features or treat local countdown as closure authority. Do not start Phase 07 without an explicit request.
