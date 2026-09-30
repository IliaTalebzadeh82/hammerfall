# Current handoff — Phase 12.5 in progress

Updated: 2026-10-01. The user explicitly started Phase 12.5 as a cross-phase
correctness and production-hardening pass over the completed Phase 0–12 system.
Phase 13 observability has not begun. Use `AGENTS.md`, the
[Phase 12.5 specification](../phases/phase-12-5.md), [context map](../context-map.md) and the active
[Phase 12.5 ExecPlan](../plans/phase-12-5-hardening-execplan.md). The plan holds
the finding ledger, decisions, Evidence Index and next-session action; do not
reconstruct the previous conversation or read archived prompts.

Session 1 reviewed auction/proxy/closing/idempotency, public revision and
outbox, both publishers/consumers, Redis/reconciliation/leases, SQL schema,
API/security config, frontend retry and CI. It repaired public snapshot
cross-field validation shared by Kafka and Redis, outbox insertion wall-time
semantics and model readonly identity/payload, a stale expiry after a blocked
lease reclaim, SQL checks for domain snapshot type/object shape, and an explicit
production `API_ALLOWED_HOSTS` requirement. PostgreSQL remains auction
authority; no bid, close, proxy or frontend protocol changed. New occurrence
semantics apply only to new outbox rows. See [event model](../event-model.md),
[projection architecture](../architecture/projections-and-reconciliation.md)
and [ADR-013](../adr/013-bounded-reconciliation-scan-ownership.md).

Focused evidence: 44 integration examples passed on isolated PostgreSQL/Redis
(seed 17640); 78 adjacent auction/projection examples passed (seed 22605);
changed Ruby lint 12/12 files clean and Zeitwerk passed. Production boot
accepted an explicitly configured host and rejected an empty host list.
One intermediate Redis DB 0 test run collided with the running development
projection consumer; the isolated DB 1 rerun passed. Broad Phase 12.5
regression, live Kafka failure campaign, browser/runtime checks and hosted CI
have not run. The demo API is still unauthenticated and not public-ready.

Next fresh session: measure and decide the publisher database-lock/I/O design,
resolve idempotency-key HMAC/privacy and request-size boundary, then run the
planned operational failure/sabotage campaign. The ExecPlan records exact
deferred findings and limits. Do not start Phase 13.
