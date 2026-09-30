# Phase 02 — Correct Concurrent Bidding

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's correct concurrent bidding scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 01 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [auction-state](../architecture/auction-state.md), [bidding](../architecture/bidding.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Implement:

- transactional bid placement
- authoritative bid ordering
- PostgreSQL locking strategy
- bid increments
- stale bid rejection
- concurrency tests

Run simultaneous bid tests.

Produce ADR.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Run simultaneous bids through separate PostgreSQL sessions and Rails processes; prove ordering, fresh-minimum rejection and no lost update. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not substitute process-local synchronization for the database coordination contract. Do not start Phase 03 without an explicit request.
