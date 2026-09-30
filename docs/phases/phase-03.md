# Phase 03 — Automatic Bidding

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's automatic bidding scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 02 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [bidding](../architecture/bidding.md), [auction-state](../architecture/auction-state.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Implement:

- private max bid
- automatic bidding algorithm
- tie behavior
- concurrency behavior
- comprehensive tests

Document algorithm with examples.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test equal maxima, incumbent versus challenger, simultaneous raises, manual offers above/equal to protection, binding policy, privacy and rollback. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not expose private ceilings or resolve proxy counters asynchronously. Do not start Phase 04 without an explicit request.
