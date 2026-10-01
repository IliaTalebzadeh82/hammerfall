# Current handoff — Phase 12.5 finalization, hosted CI pending

Updated: 2026-10-01. Phase 12.5 remains active until hosted CI and the final
repository review are recorded. Phase 13 has not begun. Read `AGENTS.md`, the
[Phase 12.5 specification](../phases/phase-12-5.md) and the active
[ExecPlan](../plans/phase-12-5-hardening-execplan.md). The plan holds all finding
dispositions, decisions, exact local results and the Evidence Index. Use the
[context map](../context-map.md) for targeted remaining work; do not reconstruct
prior sessions.

Session 1 (`59e1229`) repaired public snapshot semantics, outbox occurrence
time and model readonly fields, lease reclaim expiry, outbox SQL structure and
production host defaults. Session 2 (`bd6f648`) retained transaction-held
Sidekiq/Kafka delivery after real PostgreSQL contention and live Kafka
failure/crash evidence. Same-row cross-path publication can delay; different
rows progress. No capacity or whole-cycle deadline claim exists. HMAC conversion
for unkeyed idempotency digests and a streaming pre-parse body limit remain
future Security/public-ingress work before any public deployment. The demo API
is unauthenticated and not public-ready.

Finalization found and repaired one additional pure deadline invariant:
`starts_at < original_ends_at <= ends_at` now holds in Auction validation,
shared Kafka/Redis public validation and a PostgreSQL CHECK. Local development
and test databases had no violating rows before migration. Focused repair tests
passed 127 examples; the post-repair full backend suite passed 424 examples
with 0 failures and 3 intentionally gated live Kafka examples. All three were
run separately and passed. RuboCop (112 files), Brakeman (0 warnings),
Zeitwerk and bundler-audit passed. Frontend lint/format/types, 73 tests and
production build passed.

Compose rebuilt and all relevant services were healthy. Existing health,
Kafka, publisher, scheduler, closer, sequential/concurrent/proxy and pruning
smokes passed. Two Rails processes passed idempotency recovery and cross-process
Cable checks. Real Chrome Playwright passed 7/7 after the repair, including
lost-response retry, realtime recovery and autonomous closer. Exact commands,
seeds and logs are in the ExecPlan.

Next action: commit and push the final candidate via the working SSH remote;
inspect actual hosted GitHub Actions API, web and Compose jobs. Fix any genuine
CI failure, then record the run URL/SHA/jobs, complete final documentation and
adversarial review, leave a clean tree and close Phase 12.5 only if its gates
are met. Do not begin Phase 13.
