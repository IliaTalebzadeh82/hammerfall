# Phase 00 — Repository Foundation

Status: Complete (see docs/progress.md for evidence)

## Goal

Deliver the roadmap's repository foundation scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Repository inspection and a working development environment. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [system-boundaries](../architecture/system-boundaries.md), [operations-and-security](../architecture/operations-and-security.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Create:

- repository structure
- README skeleton
- architecture docs skeleton
- ADR directory
- backend app
- frontend app
- Docker development foundation
- formatting/linting
- basic CI

No Kafka.

No Redis unless needed by framework tooling.

No Kubernetes.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Boot the Rails and Next.js foundations, check Compose, lint, tests and CI configuration. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

No Kafka, Redis unless framework tooling requires it, or Kubernetes. Do not start Phase 01 without an explicit request.
