# Phase 19 — Terraform + Gcp Architecture

Status: Planned; begin only on an explicit request

## Goal

Deliver the roadmap's terraform + gcp architecture scope while preserving PostgreSQL auction authority and a working repository.

## Prerequisites

Phase 18 completed and verified; review its handoff. Read `AGENTS.md`, `docs/handoffs/latest.md`, and relevant architecture: [operations-and-security](../architecture/operations-and-security.md), [system-boundaries](../architecture/system-boundaries.md). Review applicable ADRs and implementation before changing an established contract.

## Scope and requirements

The original roadmap requirements are preserved below:

Build deployable or near-deployable infrastructure definitions.

Document estimated architecture and costs.

Do not create unnecessary paid resources without explicit instruction.

Apply the detailed cross-cutting rules in the linked architecture documents and existing ADRs. For completed phases, those ADRs record adopted behavior where the original roadmap left a policy open.

## Invariants

Preserve the canonical guarantees in `docs/invariants.md`: one PostgreSQL authority, correct serialization/ordering and lifecycle, private maximums, atomic command outcome and explicit failure limits. New derived systems may be stale or unavailable without changing auction truth.

## Verification

Validate infrastructure definitions and documented cost/security assumptions without creating paid resources implicitly. Use focused tests during development and run relevant full regression, lint and local/Compose checks before declaring the phase complete. Record actual results and limits.

## Definition of done

Implementation works; tests and lint pass; relevant integration verification passes; docs and any substantial ADR are updated; Docker/local setup still works; no known serious correctness bug remains. Update `docs/progress.md` with evidence and rewrite `docs/handoffs/latest.md`. End at this phase boundary.

## Out of scope

Do not incur paid cloud costs without explicit authorization. Do not start Phase 20 without an explicit request.
