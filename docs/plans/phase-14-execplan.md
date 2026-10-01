# Phase 14 — Load Testing ExecPlan

Status: Final local gates complete; hosted CI pending (2026-10-01).
Current milestone: Verify the final revision in hosted CI, then close Phase 14.

## Protocol

- Use the unchanged Phase 13 Compose configuration and observability stack for the primary local comparison. Record exact Git SHA, UTC time, host and Docker/k6 versions, CPU/RAM, container limits and service settings for each retained run. This shared host is a comparative local test, not a production capacity estimate.
- Create isolated benchmark users and auctions with a unique run label; record their IDs and configuration in a manifest. Do not reset or delete unrelated data. Use fixed random seeds/workload proportions and explicitly record VUs, duration, achieved iterations, dropped iterations and generator CPU/memory. Warm each fixture with a short, separate low-load run; retain cold-start observations separately if interesting.
- Run at increasing documented load levels. Keep telemetry enabled for primary measurements. Store machine output separately from concise result reports under `docs/benchmarks/`. Report p50/p95/p99 only with sample counts; classify accepted, domain rejection, replay, conflict, client error, server error and timeout separately. Bounded metric tags only.
- Take before/after observations of PostgreSQL sessions and locks, API/worker CPU and memory, pool/lock metrics, outbox backlog/oldest age, Kafka lag and reconciliation. Sample diagnostics sparingly. Distinguish generator, host, container, application and database limitations.
- After mutation runs, independently query PostgreSQL to verify sequence uniqueness/order, price/leader against history, winner if closed, maximum ceilings, revision/outbox consistency and duplicate command effects. Do not infer correctness from HTTP alone.
- Retain all meaningful runs, including failed attempts. Repeat representative baseline and hot runs before a bottleneck conclusion. Do not tune application configuration or declare SLO/capacity from these runs.

## Decisions

- Benchmark fixtures use the demo identity model and current HTTP contract. Fixture labels allow scoped cleanup; fixture data stays distinct from result documents.
- The first milestone uses the existing Compose stack. Closing storm, WebSocket fanout and saturation belong to the next milestone after a hard checkpoint if substantial work remains.
- Session 2 stopped continuous hot escalation at 64 VUs after throughput flattened and p95 rose; the 1,000-bidder requirement was tested separately as a one-shot final-ten-second burst. A 600-bidder step was the highest clean burst observed after 1,000 hit the API's 1,024-file soft limit. No pool, file limit or application tuning was adopted.
- Session 2 retained the 1,000 HTTP failure and first invalid fanout attempt. The extended harness was committed as `4f7932e` after the runs; their application HEAD snapshots show `fec1826` while harness changes were in the working tree. [Session 2 analysis](../benchmarks/phase-14-session-2.md) records exact provenance and limitations.

## Progress

Completed: Session 1's pinned k6 harness and normal/hot/duplicate measurements (`c86f4f8`, `fec1826`); Session 2 closing, 400/600/1,000 final-ten-second challenges, 50/200/500 fanout, 8/16/32/64 hot progression, controlled eight-row comparison, normal/hot repeats, targeted duplicate burst, checker/classifier sabotage and recovery observation. Extended harness `4f7932e`; the [benchmark index](../benchmarks/README.md) and [Session 2 analysis](../benchmarks/phase-14-session-2.md) hold actual runs and evidence classes. No auction business rule or permanent runtime setting changed.
Verified: Focused Python/Bash/Ruby syntax, live k6 runs, authoritative PostgreSQL checks after all major mutation runs, closing/extension/winner checks, all 400/600/1,000 final-ten checkers, fanout receipts and HTTP classifications, nine-auction Redis/PostgreSQL recovery parity, empty selected outbox/Sidekiq queues, restored sabotage check. Clean stepped hot runs had zero unexpected HTTP errors. The 1,000 attempt launched all VUs but had 28 API `EMFILE` 500s and 64 k6 timeouts; 911 completed DB commands reconciled against 908 successful/expected HTTP responses. No state-check failure. Exact p50/p95/p99 and limitations are in the analysis.
Final local verification: 24 retained reports/reconciliations reviewed; full backend/web/security/build and Compose/runtime/real-Chrome gates passed after test Redis isolation. [Final review](../benchmarks/phase-14-final.md) and [gate logs](../benchmarks/phase-14-final-gates/README.md) hold the concise evidence. No performance optimization or business-rule change was made.
Remaining: Hosted CI on the final revision, then close the handoff/progress and Phase 14 boundary. Do not begin Phase 15.
Known failures/limitations: The first full local gate failed 11 Redis projection examples because the live Compose stack and native tests shared Redis DB 0; isolating tests to DB 15 passed the affected specs and full rerun. First fanout run omitted an allowed Origin and all handshakes failed; the controlled one-connection-per-VU series starts at 50. Closing shell postprocessing was interrupted by editing a running Bash file; measured k6 traffic completed and manual checker passed. First closing checker assumed one extra initial revision; corrected and sabotage-verified. The 1,000 attempt was limited by the API open-file soft limit and its single during snapshot missed peak load. Hot 8-VU repeatability varied about 16% in HTTP rate. Pool checkout and Puma admission waits were not instrumented. The optional stable telemetry-on/off comparison was not performed. Earlier Session 1 exploratory caveats remain in the benchmark index.
Relevant files: `load-tests/`, `apps/api/script/benchmark_verify.rb`, `docs/load-testing.md`, `docs/benchmarks/`, `docs/api.md`, `docker-compose.yml`.
Relevant ADRs: ADR-003 auction serialization, ADR-005 deadlines, ADR-006 idempotency.
Next action: Push the committed final local-gate revision, inspect hosted API/web/Compose jobs, repair a real failure if found, then record the hosted run and mark Phase 14 complete. Keep Phase 15 out of scope.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Starting state | `git rev-parse HEAD`; `docker compose ps` | Phase 13 `44864cd`; API, DB, Redis, Kafka, web healthy | Initial inspection |
| Focused harness checks | `python3 -m py_compile load-tests/*.py`; `bash -n`; `ruby -c`; `git diff --check` | Passed | Terminal output; harness commit `c86f4f8` |
| Normal primary | `load-tests/benchmark.sh normal 4 30s` | 2,055 requests; 0 unexpected errors; 0 checker failures | [Report](../benchmarks/p14-20261001T133208Z-31a8c49a-normal/report.md) and adjacent raw/snapshots |
| Hot primary | `load-tests/benchmark.sh hot 8 30s` | 1,519 bids; 370 accepted/1,149 rejected; 0 unexpected errors; 0 checker failures | [Report](../benchmarks/p14-20261001T133320Z-03f35c6c-hot/report.md) and adjacent raw/snapshots |
| Duplicate primary | `load-tests/benchmark.sh duplicate 8 15s` | 2,381 replay/125 conflict/1 original; 1 bid; 0 checker failures | [Report](../benchmarks/p14-20261001T133436Z-1f8c4b84-duplicate/report.md) and adjacent raw/snapshots |
| Exploratory validation | Short k6 smokes; telemetry-on/off runs; hot export settlement check | Harness issues found and fixed; results retained with limitations | [Benchmark index](../benchmarks/README.md) |
| Closing storm | `load-tests/benchmark.sh closing 16 25s` | 138 accepted, 1,018 expected rejections, one +90s extension, 0.240s close lag, checker passed; postprocessing repaired | [Report](../benchmarks/p14-20261001T134853Z-f5b63800-closing/report.md), [diagnostics](../benchmarks/p14-20261001T134853Z-f5b63800-closing/diagnostics.md) |
| Hot progression | `load-tests/benchmark.sh hot 16/32/64 20s`; repeat `hot 8 30s` | ~84–101 HTTP/s across levels while p95 rose 89–935ms; lock p95 bucket ≤25–50ms; all checkers passed | [Comparison](../benchmarks/phase-14-session-2.md#hot-auction-saturation) and linked raw reports |
| Same-loop row partitioning | `load-tests/benchmark.sh distributed 16 20s 8 64` | 590 accepted in 20s versus 111 hot; changed success mix; checker passed | [Report](../benchmarks/p14-20261001T140112Z-770c0b73-distributed/report.md) |
| Final-ten challenges | `load-tests/benchmark.sh challenge 400/600/1000 75s` | 400/600 clean; 1,000 launched with 28 `EMFILE` 500s and 64 timeouts; all PG checkers passed | [Comparison](../benchmarks/phase-14-session-2.md#closing-storm-and-final-ten-second-challenge), [1,000 diagnostics](../benchmarks/p14-20261001T140304Z-02bb53d7-challenge/diagnostics.md) |
| WebSocket fanout | `load-tests/benchmark.sh fanout 50/200/500 20s` | All requested subscriptions confirmed; 1,400/5,600/13,500 k6 invalidations; zero socket failures | [Comparison](../benchmarks/phase-14-session-2.md#action-cable-fanout-and-replay) |
| Repeatability and H6 | `normal 4 30s`; `hot 8 30s`; `burst 64 5s` | Normal repeat 63.85 versus 68.37 HTTP/s; hot 84.26 versus 100.83; burst one original +127 replays, later-wave p95 52ms | [Analysis](../benchmarks/phase-14-session-2.md) and linked raw reports |
| Recovery and sabotage | Selected PG/Redis/Sidekiq read; transaction-only checker corruption; intentional 404 classification | Nine selected revisions matched; queues empty; checker detected mismatch then passed after rollback; classifier gate failed as intended | [Recovery](../benchmarks/recovery-check.json), [checker](../benchmarks/validation-checker-sabotage.md), [classifier](../benchmarks/validation-classifier-sabotage/README.md) |
| Session 2 focused harness checks | `python3 -m py_compile load-tests/*.py`; `bash -n load-tests/*.sh`; `ruby -c script/benchmark_verify.rb`; `git diff --check` | Passed; live scenario scripts exercised via k6 | Harness commit `4f7932e` |
| Evidence reconciliation | 24 retained `p14-*` reports and verifier JSONs | All expected raw files present; all verifier `failures` arrays empty | [Final review](../benchmarks/phase-14-final.md) |
| Initial regression failure | `scripts/check` | 439 examples, 11 failures from test/live Redis DB 0 collision | [Gate logs](../benchmarks/phase-14-final-gates/README.md) |
| Redis isolation diagnosis | 3 affected reconciliation spec files with `REDIS_URL=.../15` | 24 examples, 0 failures, 2 pending | [Gate logs](../benchmarks/phase-14-final-gates/README.md) |
| Full local regression and security | `scripts/check`; `bin/bundler-audit` | 439 examples, 0 failures, 4 pending; 73 frontend tests; Ruby/web static and build gates passed; no dependency advisories | [Gate logs](../benchmarks/phase-14-final-gates/README.md) |
| Compose/runtime | Compose config/health, scheduled jobs, Kafka and API/concurrent/proxy/prune smokes | Passed | [Gate logs](../benchmarks/phase-14-final-gates/README.md) |
| Real browser | Chrome Playwright against live Compose | 7 passed | [Gate logs](../benchmarks/phase-14-final-gates/README.md) |
| Hosted CI | Push final revision; inspect API/web/Compose jobs | Pending | This plan |
