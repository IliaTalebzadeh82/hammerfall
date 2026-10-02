# Phase 16 — Chaos Testing ExecPlan

Status: active; Session 1 checkpoint complete. Phase 17 is excluded.

Current milestone: local baseline and five failure campaigns retained.

Completed: bounded fixture/probe/fault/recovery harness; baseline, Redis loss
plus targeted reconciliation, Kafka broker outage, Sidekiq/publisher outage,
Kafka publisher SIGKILL with backlog, and live Kafka duplicate redelivery.
[Session 1 report](../chaos/session-1.md) records the observed boundaries.

Verified: starting SHA `2b9fb2fe2d7031c5a5b543afd48cf94e86ee540a`;
each retained campaign passed the direct PostgreSQL checker and final derived
comparison. Ruby syntax/RuboCop, Python compile and privacy scan passed.

Remaining: deterministic publisher crash after broker acceptance/before SQL
ack; consumer crash after SQL effect/before offset; API restart and ambiguous
same-key retry; API-only outage; worker/Cable and reconciliation failure
integration; adversarial review, broad gates and phase completion.

Known failures/limitations: Three preflight harness failures are retained and
explained in the report. No Hammerfall correctness failure was observed. The
publisher SIGKILL happened with Kafka unavailable and cannot prove the exact
post-acceptance crash window. WebSocket hint absence/resumption was not directly
observed. Prometheus samples missed short-lived fixture backlog; direct SQL
proved it. Redis loss used a fixture-key deletion, not a shared-volume wipe.

Relevant files: `scripts/chaos/run.py`, `apps/api/script/chaos_*.rb`,
`docs/chaos/`, `apps/api/script/benchmark_verify.rb`, publishers/consumers.

Relevant ADRs: ADR-010 (outbox), ADR-011 (Kafka), ADR-012 (projection),
ADR-013 (reconciliation).

Next-session starting point: read the compact handoff, this plan, and
[Session 1 report](../chaos/session-1.md). Design deterministic crash-window
hooks that do not alter production semantics, then run the two dangerous
publisher/consumer timing scenarios. Do not rerun completed campaigns without
a concrete gap or repair.

## Decisions

- Use isolated auctions and a single process orchestrator. Keep evidence public
  only; raw private idempotency keys stay in memory.
- A stopped Redis service plus deletion of the fixture's projection key after
  restart models loss of that derived key without destroying shared Sidekiq
  data or unrelated local state.
- Compare the ordinary PostgreSQL-backed GET, eventual GET and direct SQL
  verifier. A read-model response alone is never authority evidence.

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

## Campaign record

The Session 1 report records each scenario's precondition, fault, expected
degradation, correctness conditions, during state, recovery action/deadline,
observed recovery, PostgreSQL/derived verification, duplicate/retry evidence,
residual limitation and decision. Raw bounded snapshots live beside it.
