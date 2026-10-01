# Phase 12.5 — Correctness and production hardening

Status: Complete on 2026-10-01. Explicitly requested after Phase 12 and before Phase 13.
This is a cross-phase adversarial repair pass over committed Phase 0–12 behavior,
not a new product feature phase. The active [ExecPlan](../plans/phase-12-5-hardening-execplan.md)
contains findings, decisions, exact evidence, remaining work and session state.

## Scope

- Review the actual auction aggregate, proxy bidding, deadlines/closure,
  idempotency, public revisions, outbox, both publishers, Kafka codec/consumers,
  Redis projection/reconciliation, scan leases, controllers/presenters, SQL
  constraints, frontend retry/realtime, CI and security/config defaults.
- Classify findings Critical, High, Medium, Low or intentional tradeoff/no
  change. For each finding record code path, failure scenario, current/missing
  protection, repair, added complexity, required tests and decision.
- Re-evaluate public snapshot semantics, event occurrence-time meaning,
  committed event immutability, publisher transaction/I/O behavior,
  idempotency-key privacy, lease fencing, structural SQL constraints and
  pre-auth security defaults against current source and tests.
- Fix bounded, justified correctness, durability, security, operational and
  maintainability weaknesses. Use real PostgreSQL/Redis/Kafka, concurrency,
  failure injection and sabotage where those mechanisms determine behavior.
  Preserve PostgreSQL authority, the existing auction lock/time/idempotency
  protocols and privacy of private maximum, priority, origin and raw keys.
- Inspect and, where needed, repair the real GitHub Actions workflow. At
  finalization, push a coherent repair branch/commit and verify hosted jobs
  if access permits; record exact commit/run/jobs/result or precise blocker.
- Update the affected canonical docs, runbooks, invariants, learning/code maps,
  handoff and progress with actual evidence. Perform final adversarial review.

## Session lifecycle

Session 1: fresh review, correctness/data-integrity repairs and focused checks,
then a hard context checkpoint. Session 2: publisher/operational work,
idempotency privacy and maintainability decisions, failure/sabotage campaign;
checkpoint if broad verification remains. Final session: broad regression,
runtime/browser/hosted CI, documentation reconciliation and final review.
Checkpoint steps follow [context lifecycle](../context-lifecycle.md): update
ExecPlan and Evidence Index, handoff, coherent commits and clean tree, emit
`CONTEXT CHECKPOINT READY`, then stop for a fresh conversation.

Do not begin Phase 13 observability, full authentication product work,
Kubernetes, load testing or unrelated features. The demo API remains local
and unauthenticated until a separately requested security phase.
