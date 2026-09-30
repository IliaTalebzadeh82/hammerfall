# Phase 01 — Core Auction Domain

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's core auction domain scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 00 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [auction-state](../architecture/auction-state.md), [system-boundaries](../architecture/system-boundaries.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Implement:

- users
- auctions
- bids
- auction state machine
- basic REST API
- PostgreSQL schema
- validation
- basic RSpec suite

Establish authoritative PostgreSQL state.

Define invariants.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Test lifecycle transitions, schema constraints, validation, API envelopes and rollback against PostgreSQL. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not add later-phase concurrency infrastructure or event systems. Do not start Phase 02 without an explicit request.
