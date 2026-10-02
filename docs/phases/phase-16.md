# Phase 16 — Chaos Testing

Status: Active; local closure gates passed, hosted CI pending

## Goal

Deliver the roadmap's chaos testing scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 15 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [operations-and-security](../architecture/operations-and-security.md), [async-events](../architecture/async-events.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Build failure scenarios.

Verify:

- DB remains authority
- duplicate delivery safe
- event backlog recoverable
- Redis loss tolerated
- worker crashes recover
- application restart safe

Document outcomes.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Inject broker/cache/worker/API failures; prove DB authority, backlog recovery, duplicate safety and documented limits. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not describe injected failures as recovered without observing recovery. Do not start Phase 17 without an explicit request.
