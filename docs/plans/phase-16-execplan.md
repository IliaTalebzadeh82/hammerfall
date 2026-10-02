# Phase 16 — Chaos Testing ExecPlan

Status: active; Session 2 checkpoint complete. Phase 17 is excluded.

Current milestone: deterministic ambiguous crash windows and API restart retained.

Completed: Session 1's bounded outage campaigns plus Session 2's deterministic
publisher post-broker/pre-SQL-ack, audit consumer post-effect/pre-offset,
API restart, committed/uncommitted same-key retry, API-only outage/direct
derived-state observation, and replay-short-circuit sabotage.
[Session 1](../chaos/session-1.md) and [Session 2](../chaos/session-2.md)
record the observations and invalid harness attempts.

Verified: Session 1 starting SHA `2b9fb2fe2d7031c5a5b543afd48cf94e86ee540a`;
Session 2 starting SHA `e45987e03c6b40f1612c406cb771435ee8e17276`.
Every passing retained campaign passed direct PostgreSQL verification and final
derived comparison. Session 2's relevant RSpec files passed 46 examples,
0 failures, 1 gated live-Kafka pending. Focused static/privacy checks are
indexed below.

Remaining: final browser REST recovery/Cable scenario if feasible, full backend
and frontend regression/lint, local runtime and hosted CI gates, final
adversarial review, documentation reconciliation and Phase 16 closure. Phase 17
requires a separate request. Reconciliation crash is supported by Phase 12
lease/fencing tests and Session 1 repair; no redundant Session 2 campaign was
run. Browser notification receipt was not directly observed.

Known failures/limitations: Session 1 has three preflight failures; Session 2
has four invalid harness attempts retained and explained. No Hammerfall
correctness failure was observed. Session 2 directly proved the exact publisher
and audit consumer crash windows that Session 1 did not. Sidekiq job execution
and reconciliation scan progress during API outage were not counted; their
process independence was observed. WebSocket/browser recovery remains untested
in Phase 16. Prometheus missed short-lived fixture backlog; direct state is
the proof. Redis loss used fixture-key deletion, not a shared-volume wipe.

Relevant files: `scripts/chaos/run.py`, `session2*.py`,
`apps/api/app/services/chaos_crash.rb`, `apps/api/script/chaos_*.rb`,
`docs/chaos/`, `apps/api/script/benchmark_verify.rb`, publishers/consumers,
idempotency executor.

Relevant ADRs: ADR-010 (outbox), ADR-011 (Kafka), ADR-012 (projection),
ADR-013 (reconciliation).

Next-session starting point: read the compact handoff, this plan and
[Session 2 report](../chaos/session-2.md). Do not rerun passed campaigns without
a code change or concrete gap. Run final broad regression/lint and browser
REST recovery/Cable verification; inspect current CI/runtime needs; then
adversarially review and complete Phase 16 if all gates pass. Do not start
Phase 17.

## Decisions

- Use isolated auctions and a single process orchestrator. Keep evidence public
  only; raw private idempotency keys stay in memory.
- A stopped Redis service plus deletion of the fixture's projection key after
  restart models loss of that derived key without destroying shared Sidekiq
  data or unrelated local state.
- Compare the ordinary PostgreSQL-backed GET, eventual GET and direct SQL
  verifier. A read-model response alone is never authority evidence.
- Scope local/test-only process-death hooks by exact boundary plus event or
  auction ID. Use synchronous `Process.exit!` for the HTTP boundary because a
  self-sent signal allowed one Puma response to complete. Recreate API from
  base Compose after each fault to clear injected environment. Atomically claim
  a container-local marker so a respawned Puma process cannot repeat the fault.
- Treat observed broker duplicate logs and unchanged durable audit counts as
  distinct claims. Retain Kafka committed-offset snapshots for consumer death.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Starting state | `git rev-parse HEAD`, `git status --short` | requested SHA, clean | this plan |
| Baseline | `python3 scripts/chaos/run.py baseline` | PASS; 3 audit effects, Redis rev 3, checker clear | [run](../chaos/p16-20261002T003553Z-784dea9d/) |
| Redis stop/key loss | `python3 scripts/chaos/run.py redis` | PASS WITH EXPECTED DEGRADATION; fallback, pending rows, repair and convergence | [run](../chaos/p16-20261002T004412Z-1d3bc497/) |
| Broker stop | `python3 scripts/chaos/run.py kafka` | PASS WITH EXPECTED DEGRADATION; 2 Kafka pending, 17.38 s observed recovery | [run](../chaos/p16-20261002T003714Z-edb14514/) |
| Notification worker/publisher stop | `python3 scripts/chaos/run.py worker` | PASS WITH EXPECTED DEGRADATION; 2 Sidekiq pending, drained | [run](../chaos/p16-20261002T003751Z-cfba7bd1/) |
| Publisher SIGKILL | `python3 scripts/chaos/run.py publisher` | PASS WITH EXPECTED DEGRADATION; 2 Kafka pending, stable event-ID list across crash/recovery | [run](../chaos/p16-20261002T004652Z-fbb18b64/) |
| Duplicate delivery | `python3 scripts/chaos/run.py duplicate` | PASS; broker acknowledged, both consumers logged duplicate, one durable effect | [run](../chaos/p16-20261002T004331Z-4423b674/) |
| Focused static checks | Python `py_compile`; Ruby `-c`; `bundle exec rubocop` on 3 scripts | PASS; 3 Ruby files, no offenses | Session 1 report |
| Privacy scan | `rg -i` for sensitive field/header patterns in retained JSON/logs | PASS; no matches | Session 1 report |
| Publisher post-acceptance crash | `python3 scripts/chaos/session2.py publisher` | PASS; broker accepted, SQL ack pending, duplicate logs in both groups, 1/1 audit effect | [run](../chaos/p16-20261002T010633Z-c0787859/) |
| Audit post-effect/pre-offset crash | `python3 scripts/chaos/session2.py consumer` | PASS WITH EXPECTED DEGRADATION; DB effect 1/1 while offset 2274, redelivery duplicate, offset 2275 | [run](../chaos/p16-20261002T010710Z-6549301c/) |
| API restart and ambiguous commands | `python3 scripts/chaos/session2_api.py` | PASS WITH EXPECTED DEGRADATION; lost responses, committed replay, uncommitted rollback/retry, API-only drain | [run](../chaos/p16-20261002T011412Z-7f99f9b8/) |
| API-only direct projection and worker observation | `python3 scripts/chaos/session2_api_only.py` | PASS WITH EXPECTED DEGRADATION; API exited, both outboxes drained, audit and Redis revision 4 | [run](../chaos/p16-20261002T011754Z-6948c6d6/) |
| Idempotency replay sabotage | Temporary `yield` in completed branch; `rspec spec/requests/idempotency_spec.rb:114`; restore | Expected failure: current `bid_too_low` replaced historic 201; restored focused suite green | [failing log](../chaos/sabotage-idempotency-replay.log), [restored log](../chaos/session2-focused-tests.log) |
| Relevant RSpec files | `bundle exec rspec spec/integration/kafka_outbox_spec.rb spec/requests/idempotency_spec.rb spec/services/chaos_crash_spec.rb` | PASS; 46 examples, 0 failures, 1 gated live-Kafka pending | [log](../chaos/session2-relevant-rspec.log) |
| One-shot API hook | Two scoped Rails runner invocations in API container | PASS; exit 137 with marker, then exit 0 without second marker | [result](../chaos/session2-hook-once.json) |
| Ruby/Python static checks | Ruby `-c` (6 files), Python AST parse (4 files), targeted RuboCop | PASS; Ruby/Python parse, 9 Ruby files without offenses | Session 2 report |
| Raw-evidence privacy and local links | Pattern scan of Session 2 logs/JSON/YAML; local Markdown link resolution | PASS; zero sensitive-pattern matches, zero missing local links | Session 2 report |

## Campaign record

Session reports record each campaign's precondition, exact fault point,
degradation, before/after state, recovery, direct verification, duplicate/retry
counts, limits and decision. Bounded raw snapshots live beside them.
