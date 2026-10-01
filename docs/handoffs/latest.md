# Current handoff — Phase 12.5 complete

Updated: 2026-10-01. Phase 12.5 correctness and production hardening is complete;
Phase 13 has not begun. Start any future phase only on explicit request. Read
`AGENTS.md`, the requested [phase specification](../phases/) and the
[context map](../context-map.md). The closed
[Phase 12.5 ExecPlan](../plans/phase-12-5-hardening-execplan.md) holds the
finding ledger, decisions and verification evidence; use it when a later task
touches these contracts.

Session 1 (`59e1229`) repaired public snapshot semantics, outbox occurrence
time and model readonly fields, lease reclaim expiry, outbox SQL structure and
production host defaults. Session 2 (`bd6f648`) retained transaction-held
Sidekiq/Kafka delivery after real PostgreSQL contention and live Kafka
failure/crash evidence. Finalization (`390b92f`) added the missing
`starts_at < original_ends_at <= ends_at` relation to Auction validation,
Kafka/Redis public validation and SQL, with regression tests and canonical
contract updates. No known serious correctness defect remains within the demo
scope.

Post-repair local backend regression passed 424 examples with 0 failures and 3
intentionally gated Kafka examples; all three separately passed against real
Kafka. RuboCop passed 112 files, Brakeman found 0 warnings, Zeitwerk and
bundler-audit passed. Frontend lint/format/types, 73 Vitest tests and production
build passed. Full Compose startup and API/Kafka/publisher/scheduler/closer
smokes passed. Two Rails processes passed idempotency and cross-process Cable
checks. Real Chrome Playwright passed 7/7 after the deadline repair.

Hosted CI was repaired and passed: API, web and Compose jobs all succeeded on
`11358387bf197e776e4698a70bf9373190bc672f` in
[run 36844131696](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36844131696),
including API RSpec and real browser scenarios. API PostgreSQL/Redis now start
through Compose because the GitHub service-container creation failed before
checkout in two runs. Brakeman was updated to 8.1.0 to satisfy its latest
version gate. The Compose job installs browser dependencies before stack startup
and uses the runner's installed Chrome. See the ExecPlan Evidence Index for
commands, seeds and intermediate failures.

Retained limits: both publishers hold an outbox row lock and DB connection
across external I/O; no whole-cycle network deadline or measured production
capacity exists. Older event rows retain transaction-start `occurred_at`.
A stalled scan row can outlive its lease. Unkeyed idempotency digests expose
weak keys to offline guessing after a DB compromise, and no pre-parse JSON
byte cap exists. The API is unauthenticated demo software and must not be
exposed publicly. HMAC rollout, public ingress limits and operational scaling
need separate reviewed work. Do not claim production readiness or begin
Phase 13 from this handoff alone.
