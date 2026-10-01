# Current handoff — Phase 14 final local gates passed

Updated: 2026-10-01. Phase 14 load experiments and final local checks are
complete; hosted CI on the final revision remains the completion gate. Resume
with the [Phase 14 ExecPlan](../plans/phase-14-execplan.md),
[final review](../benchmarks/phase-14-final.md), and
[benchmark index](../benchmarks/README.md). Do not begin Phase 15.

The k6 harness, closing storm, 8/16/32/64 hot steps, one-row/eight-row
comparison, 400/600/1,000 final-ten bursts, 50/200/500 Cable fanout steps,
normal/hot repeats and duplicate burst are retained under `docs/benchmarks/`.
Every major mutation run passed authoritative PostgreSQL verification. The
1,000 attempt reached the API's 1,024-open-file limit, causing 28 server
errors and 64 timeouts; its committed outcomes were reconciled. These short
shared-host runs establish no production capacity. No auction rule or
permanent runtime tuning changed.

The first full local `scripts/check` failed 11 Redis projection examples
while the live Compose stack and native tests shared Redis DB 0. A focused
24-example rerun against DB 15 passed, and `scripts/check` now isolates test
Redis there. The complete rerun passed 439 examples, 0 failures, 4 pending;
frontend lint/format/types/build and 73 tests passed, as did Ruby static and
security checks and bundler-audit. Compose/runtime smokes and all seven real
Chrome scenarios passed. [Final gate logs](../benchmarks/phase-14-final-gates/README.md)
and the ExecPlan Evidence Index hold exact commands and limits.

Next: commit/push final local-gate changes, inspect hosted API/web/Compose
jobs, repair any real failure, then record the hosted run and mark Phase 14
complete in progress, handoff and plan. No benchmark rerun is warranted by
current evidence. Pool checkout and Puma admission waits remain unmeasured;
the stable telemetry overhead pair was not run. Phase 15 is only an
evidence-classified investigation list, not active work.
