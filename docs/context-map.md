# Context routing and migration map

`AGENTS.md` is the routine instruction entry point. [Latest handoff](handoffs/latest.md) is the compact current-state entry point. The [context lifecycle and ExecPlan convention](context-lifecycle.md) governs checkpoints and resumption; `docs/plans/phase-10-execplan.md` records completed Phase 10 evidence. [Phase specifications](phases/) hold the scope for each requested phase. [Progress](progress.md) is historical evidence, not startup context; the [archived original](archive/masterprompt-original.md) is for a specific missing historical fact only. Do not start Phase 11 without an explicit request.

| Working on | Required context | Optional targeted context |
|---|---|---|
| Any repository task | `AGENTS.md` | This map |
| Substantial phase kickoff or resume | Latest handoff, current phase spec, active ExecPlan if resuming | Context lifecycle convention; targeted architecture/ADR/source |
| Starting Phase 11 | `AGENTS.md`, `docs/handoffs/latest.md`, `docs/phases/phase-11.md` | `docs/architecture/projections-and-reconciliation.md`, ADR-011 and Phase 10 evidence |
| Auction lifecycle or schema | `docs/architecture/auction-state.md`, current phase spec | `docs/domain-model.md`, `docs/invariants.md`, ADR-002/003 |
| Bidding/proxy/concurrency | `docs/architecture/bidding.md`, auction state | ADR-003/004, relevant tests |
| Deadline/closing | `docs/architecture/deadlines.md` | ADR-005, closer specs |
| Retry/idempotency | `docs/architecture/idempotency.md` | ADR-006/007, API contract |
| Frontend or realtime | `docs/architecture/realtime-and-frontend.md`, `apps/web/AGENTS.md` | `docs/frontend.md`, `docs/realtime.md`, ADR-007/008 |
| Jobs/events/outbox/Kafka | `docs/architecture/async-events.md`, applicable phase spec | `docs/event-model.md`, `docs/failure-model.md` |
| Redis projection/reconciliation | `docs/architecture/projections-and-reconciliation.md`, applicable phase spec | `docs/consistency-model.md` |
| Security/operations/load/deployment | `docs/architecture/operations-and-security.md`, applicable phase spec | Current production/readiness/runbook/benchmark evidence |
| Final phase verification | Current phase spec, latest handoff, changed architecture/ADR | `docs/progress.md` for prior actual evidence |
| Historical evidence | Relevant `docs/progress.md` phase heading/anchor | Completed ExecPlan or specific Git commit |

## Recommended Codex session lifecycle

1. Start a fresh session for a substantial new phase, only when explicitly requested. Read `AGENTS.md`, the latest handoff and current phase spec; read the active ExecPlan when resuming.
2. Use this map for targeted architecture/ADR/source/tests, then create or update the phase ExecPlan. Follow the [checkpoint and evidence convention](context-lifecycle.md).
3. Implement and verify rigorously. At a substantial milestone, persist state and evidence, mark `CONTEXT CHECKPOINT READY`, and resume significant remaining work in a fresh session.
4. At phase end, update durable docs/ADRs and actual progress evidence, rewrite the compact handoff, leave a clean tree and stop at the phase boundary.

## Master prompt migration trace

The rows below cover every top-level numbered section and each named roadmap phase in the 2,644-line original. Subheadings within a numbered section inherit that row's destination; the notes identify multi-topic sections. The archive retains the exact source for audit. “Planned” means a requirement is preserved for a later phase, **not** that it is implemented.

| Original masterprompt section | Classification | New destination | Action / discrepancy |
|---|---|---|---|
| Opening project brief | Product/architecture | `docs/architecture/system-boundaries.md`; `README.md` | Preserved engineering focus and narrow scope. |
| 1. PRIMARY PRODUCT IDEA | Product | `docs/architecture/system-boundaries.md` | Preserved user/operator scope; operator-phase assignment flagged in review. |
| 2. CORE ENGINEERING QUESTION | Architecture | `docs/architecture/system-boundaries.md` | Preserved core correctness question. |
| 3. TECHNOLOGY STACK | Architecture/phase | `docs/architecture/system-boundaries.md; docs/architecture/async-events.md; docs/architecture/operations-and-security.md` | All backend, frontend, realtime, database, jobs, streaming, cache, observability, testing, local, CI and deployment subheadings routed; future technology explicitly planned. |
| 4. INITIAL ARCHITECTURAL PRINCIPLE | Architecture | `docs/architecture/system-boundaries.md; docs/adr/001-modular-monolith.md` | Preserved modular monolith, extraction criteria and ADR rule. |
| 5. REQUIRED DOMAIN MODEL | Domain | `docs/architecture/auction-state.md; docs/architecture/bidding.md; docs/architecture/idempotency.md; docs/architecture/async-events.md` | User/Auction/Bid/AutomaticBid/OutboxEvent/IdempotencyRecord routed; actual private model is MaximumBid. |
| 6. DOMAIN INVARIANTS | Invariants | `docs/architecture/auction-state.md; docs/architecture/bidding.md; docs/architecture/async-events.md; docs/architecture/projections-and-reconciliation.md; docs/invariants.md` | All 15 preserved; event/projection clauses are future requirements, not Phase 7 guarantees. |
| 7. AUCTION ORDERING | Architecture | `docs/architecture/auction-state.md; docs/adr/003-auction-concurrency-control.md` | Adopted auction-local sequence; IDs/timestamps not authority. |
| 8. CONCURRENT BIDDING | Architecture/phase | `docs/architecture/auction-state.md; docs/phases/phase-02.md; docs/adr/003-auction-concurrency-control.md` | Adopted row lock; actual numbered ADR replaces suggested filename. |
| 9. AUTOMATIC BIDDING | Architecture/phase | `docs/architecture/bidding.md; docs/phases/phase-03.md; docs/adr/004-proxy-bidding.md` | Adopted binding, no-cancellation policy and tested tie rules. |
| 10. AUCTION CLOSING | Architecture/phase | `docs/architecture/deadlines.md; docs/phases/phase-04.md; docs/adr/005-auction-deadlines-and-soft-close.md` | Adopted DB-clock closer; actual numbered ADR replaces suggested filename. |
| 11. SOFT-CLOSE / ANTI-SNIPING | Architecture/phase | `docs/architecture/deadlines.md; docs/phases/phase-04.md` | Adopted final-60/+90 policy; realtime notification now generic revision hint. |
| 12. IDEMPOTENCY | Architecture/phase | `docs/architecture/idempotency.md; docs/phases/phase-05.md; docs/adr/006-client-command-idempotency.md` | Preserved same-key retry, conflict, concurrency and retention. |
| 13. TRANSACTIONAL OUTBOX | Architecture/phase | `docs/architecture/async-events.md; docs/phases/phase-09.md; docs/adr/010-transactional-public-outbox.md` | Implemented in Phase 9; crash/duplicate/order evidence in its ExecPlan. |
| 14. DOMAIN EVENTS | Architecture/phase | `docs/architecture/async-events.md; docs/phases/phase-10.md; docs/adr/011-kafka-domain-events.md` | Implemented public versioned snapshots and schema/privacy; trace context awaits observability phase. |
| 15. REAL-TIME UX | Architecture/phase | `docs/architecture/realtime-and-frontend.md; docs/phases/phase-07.md; docs/api.md` | Adopted REST recovery/invalidation; stale bid error contract remains in API. |
| 16. FRONTEND EXPERIENCE | Product/phase | `docs/architecture/realtime-and-frontend.md; docs/phases/phase-06.md; docs/frontend.md` | Preserved focused responsive auction UI, controls and shadcn basis. |
| 17. READ MODELS | Architecture/phase | `docs/architecture/projections-and-reconciliation.md; docs/phases/phase-11.md` | Projection remains planned; PostgreSQL authority preserved. |
| 18. RECONCILIATION | Architecture/phase | `docs/architecture/projections-and-reconciliation.md; docs/phases/phase-12.md` | Planned drift detection, repair, metrics, logging and operator boundary. |
| 19. SIDEKIQ | Architecture/phase | `docs/architecture/async-events.md; docs/phases/phase-08.md` | Implemented bounded-retry notification and read-only sweep jobs in Phase 8. |
| 20. KAFKA CONSUMERS | Architecture/phase | `docs/architecture/async-events.md; docs/phases/phase-10.md` | Audit consumer implemented with duplicate/restart/replay/poison handling; projection remains Phase 11. |
| 21. FAILURE MODEL | Operations | `docs/architecture/operations-and-security.md; docs/failure-model.md` | All named failures and four recovery questions retained. |
| 22. OBSERVABILITY | Operations/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-13.md` | Planned tracing of bidding/DB/outbox/async flows. |
| 23. METRICS | Operations/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-13.md` | Planned metric families and cardinality/privacy constraint. |
| 24. LOGGING | Operations/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-13.md` | Planned JSON fields and secret/private-data exclusions. |
| 25. DASHBOARDS | Operations/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-13.md` | All auction-health, messaging, consistency and runtime dashboard groups retained. |
| 26. LOAD TESTING | Verification/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-14.md` | k6 scenarios, 1,000-bidder challenge and real benchmark record retained. |
| 27. CONCURRENCY EXPERIMENT | Verification/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-15.md` | Planned low/high-contention strategy experiment; no speed-only decision. |
| 28. CHAOS / FAILURE INJECTION | Verification/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-16.md` | All Kafka/Redis/consumer/post-commit crash outcomes retained. |
| 29. PROPERTY / INVARIANT TESTING | Verification | `docs/architecture/operations-and-security.md` | Property checks for bidding, retries and projection replay retained. |
| 30. MULTI-INSTANCE TESTING | Verification/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-17.md` | Multiple-process proof and no local synchronization retained. |
| 31. SECURITY BASICS | Security | `docs/architecture/operations-and-security.md; docs/security.md` | Authentication, authorization and deployment safety remain future work; demo limitation explicit. |
| 32. RATE LIMITING | Security | `docs/architecture/operations-and-security.md; docs/security.md` | Bounded bid rate limiting and Redis failure strategy retained for future implementation. |
| 33. DATABASE DESIGN | Persistence | `docs/architecture/auction-state.md` | Indexes, plan review and named hot queries retained. |
| 34. MIGRATIONS | Persistence | `docs/architecture/auction-state.md` | Reversibility, safety and deploy-safe migration policy retained. |
| 35. API DESIGN | API | `docs/architecture/auction-state.md; docs/api.md` | Versioned REST/error envelope; actual API contract supersedes illustrative paths. |
| 36. DOCUMENTATION | Documentation | `docs/architecture/system-boundaries.md; docs/architecture/operations-and-security.md; docs/context-map.md` | Document deliverables routed; future experiments/benchmarks created when evidence exists. |
| 37. ADR FORMAT | Agent rule | `AGENTS.md; docs/architecture/system-boundaries.md` | ADR format and candidate topics retained. |
| 38. README QUALITY | Documentation | `docs/architecture/operations-and-security.md; README.md` | Honest README scope and required navigation retained. |
| 39. KUBERNETES | Infrastructure/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-18.md` | Prerequisites, workload manifests and no ornamental stateful YAML retained. |
| 40. TERRAFORM / GCP | Infrastructure/phase | `docs/architecture/operations-and-security.md; docs/phases/phase-19.md` | GCP/Terraform choices and no unnecessary cloud cost retained. |
| 41. CI/CD | Verification | `docs/architecture/system-boundaries.md; docs/architecture/operations-and-security.md; .github/workflows/ci.yml` | CI checks and no deploy credentials preserved. |
| 42. CODE QUALITY | Agent rule | `AGENTS.md` | Code clarity and anti-patterns consolidated. |
| 43. RAILS DESIGN STYLE | Agent rule | `AGENTS.md` | Thin controllers and bounded Rails abstractions consolidated. |
| 44. DATABASE AS CONCURRENCY COORDINATOR | Architecture | `docs/architecture/auction-state.md; AGENTS.md` | Database coordination across Rails instances preserved. |
| 45. CLOCKS | Architecture | `docs/architecture/deadlines.md` | DB time, UTC, scheduler/client assumptions preserved. |
| 46. EXPERIMENTATION | Product future | `docs/architecture/operations-and-security.md; docs/context-migration-review.md` | Lightweight bucketing/events preserved; phase/privacy placement needs review. |
| 47. PRODUCTION READINESS DOCUMENT | Operations | `docs/architecture/operations-and-security.md; docs/production-readiness.md` | Capacity, durability, backup, runbook and real-money gap retained. |
| 48. RUNBOOKS | Operations | `docs/architecture/operations-and-security.md` | Six operational runbooks and required template retained for future phase work. |
| 49. PHASED IMPLEMENTATION ROADMAP | Phase governance | `docs/phases/phase-00.md through phase-20.md; AGENTS.md` | All 21 roadmap phases split below; each leaves working repository. |
| 50. AGENT WORKING MODE | Agent rule | `AGENTS.md` | Autonomous implementation permission consolidated. |
| 51. DO NOT ASK UNNECESSARY QUESTIONS | Agent rule | `AGENTS.md` | Reasonable-default decision rule consolidated; external costs/irreversible choices flagged. |
| 52. NEVER HIDE PROBLEMS | Agent rule | `AGENTS.md` | Diagnose/fix/reverify; never hide failures or weaken invariants. |
| 53. NEVER FAKE RESULTS | Agent rule | `AGENTS.md` | No fabricated tests, benchmarks, operations or scalability claims. |
| 54. ARCHITECTURAL CHANGE RULE | Agent rule | `AGENTS.md` | Problem/alternatives/ADR/implementation/test/doc change sequence retained. |
| 55. TESTING RULE | Agent rule | `AGENTS.md; docs/architecture/operations-and-security.md` | Meaningful tests and real integration dependencies retained. |
| 56. DEFINITION OF DONE FOR EACH PHASE | Agent rule | `AGENTS.md; docs/phases/phase-00.md through phase-20.md` | Completion gate and progress evidence retained. |
| 57. LEARNING DOCUMENT | Documentation | `docs/architecture/operations-and-security.md; docs/learning-guide.md` | Questions and required subsystem coverage retained. |
| 58. CODE WALKTHROUGH MAP | Documentation | `docs/architecture/operations-and-security.md; docs/code-map.md` | Workflow map boundaries retained. |
| 59. INTERVIEW PREPARATION DOCUMENT | Documentation future | `docs/architecture/operations-and-security.md; docs/phases/phase-20.md` | Interview questions preserved as end-of-project deliverable. |
| 60. ENGINEERING JOURNAL | Documentation | `docs/architecture/operations-and-security.md; docs/engineering-journal.md` | Substantive discovery journal retained; diary history remains reference-only. |
| 61. FINAL SYSTEM REVIEW | Verification future | `docs/architecture/operations-and-security.md; docs/phases/phase-20.md` | Adversarial review, severity categories and critical/high fix rule retained. |
| 62. FINAL DELIVERABLE | Roadmap | `docs/architecture/system-boundaries.md; docs/phases/phase-20.md` | Breadth preserved but secondary to correctness. |
| 63. WHAT SUCCESS LOOKS LIKE | Roadmap | `docs/architecture/system-boundaries.md; docs/architecture/operations-and-security.md` | Success criteria preserved as explicit invariants/evidence and honest limitations. |
| 64. STARTING INSTRUCTION | Historical agent instruction | `docs/archive/masterprompt-original.md; docs/context-map.md` | Phase 0 bootstrap completed; unconditional continue-to-next-phase superseded by current explicit phase boundaries and user request. |

### Roadmap phase sections (inside original section 49)

| Original heading | Classification | New destination | Action |
|---|---|---|---|
| PHASE 0 — REPOSITORY FOUNDATION | Phase specification | `docs/phases/phase-00.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 1 — CORE AUCTION DOMAIN | Phase specification | `docs/phases/phase-01.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 2 — CORRECT CONCURRENT BIDDING | Phase specification | `docs/phases/phase-02.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 3 — AUTOMATIC BIDDING | Phase specification | `docs/phases/phase-03.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 4 — AUCTION CLOSING + SOFT CLOSE | Phase specification | `docs/phases/phase-04.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 5 — IDEMPOTENCY | Phase specification | `docs/phases/phase-05.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 6 — FRONTEND | Phase specification | `docs/phases/phase-06.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 7 — REAL-TIME UPDATES | Phase specification | `docs/phases/phase-07.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 8 — SIDEKIQ + REDIS | Phase specification | `docs/phases/phase-08.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 9 — TRANSACTIONAL OUTBOX | Phase specification | `docs/phases/phase-09.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 10 — KAFKA | Phase specification | `docs/phases/phase-10.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 11 — REDIS PROJECTION | Phase specification | `docs/phases/phase-11.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 12 — RECONCILIATION | Phase specification | `docs/phases/phase-12.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 13 — OBSERVABILITY | Phase specification | `docs/phases/phase-13.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 14 — LOAD TESTING | Phase specification | `docs/phases/phase-14.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 15 — PERFORMANCE ENGINEERING | Phase specification | `docs/phases/phase-15.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 16 — CHAOS TESTING | Phase specification | `docs/phases/phase-16.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 17 — MULTI-INSTANCE DEPLOYMENT | Phase specification | `docs/phases/phase-17.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 18 — KUBERNETES | Phase specification | `docs/phases/phase-18.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 19 — TERRAFORM + GCP ARCHITECTURE | Phase specification | `docs/phases/phase-19.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |
| PHASE 20 — FINAL ENGINEERING POLISH | Phase specification | `docs/phases/phase-20.md` | Original roadmap scope preserved; detailed cross-cutting rules linked; completed state stays in handoff/progress. |

### Superseded references and active-context reduction

- The original suggested unnumbered `docs/adr/auction-concurrency-control.md` and `docs/adr/auction-closing.md`; adopted decisions are `docs/adr/003-auction-concurrency-control.md` and `docs/adr/005-auction-deadlines-and-soft-close.md`. The adopted Phase 4 rule uses final-60/+90, rather than the illustrative final-30/+30 text in section 11.
- The original `AutomaticBid` concept is implemented as `MaximumBid`, with binding increase-only semantics; the original optional cancellation question was resolved as unsupported in ADR-004. OutboxEvent was implemented in Phase 9 and Kafka propagation/audit in Phase 10; Redis projection and reconciliation remain planned.
- Original section 64 instructed continuing through every phase. The earlier migration occurred after Phase 7 and required a new request for Phase 8. Treat section 64's Phase 0 startup and unconditional continuation as historical; the current handoff records Phase 8 completion and the Phase 9 gate.
- Old prompts and diagnostic narratives in `docs/progress.md` and `docs/engineering-journal.md` are retained for audit, excluded from the normal context route. Do not treat their old `masterprompt.md` references as active instructions. No debugging transcript was copied into the new handoff or architecture docs.
- A normal Phase 8 startup loads `AGENTS.md`, `docs/handoffs/latest.md`, `docs/phases/phase-08.md` and three targeted architecture files: 264 lines at migration time, versus 2,644 newline-terminated lines for the old master prompt. Further ADR/code reads depend on the actual subtask. This reduction routes detail rather than deleting it.

## Migration validation

- All 64 numbered sections and 21 roadmap phases have trace rows above. The original body is byte-identical to the committed `masterprompt.md` after the archive banner.
- Adopted invariants are routed to architecture, `docs/invariants.md` and ADRs; the Phase 9 outbox and Phase 10 Kafka propagation/audit are implemented. Projection and reconciliation remain planned. No phase's original roadmap bullets were removed from its specification.
- `AGENTS.md` holds durable process/domain guardrails only. The latest handoff describes the current completed phase and verified evidence, while chronology remains in `docs/progress.md`.
- Detailed adopted decisions have one canonical ADR or technical document; the new architecture docs route readers to those details rather than duplicating decision tables. Old prompt references in historical progress/journal text are not active instructions.
- Documentation links were checked, and no application source, schema, test, dependency or deployment configuration was changed in this migration.
