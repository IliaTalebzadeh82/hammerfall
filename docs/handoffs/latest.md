# Current handoff — Phase 14 Load Testing in progress

Updated: 2026-10-01. Phase 13 is complete; Phase 14 was explicitly requested.
Session 2 experiments are complete and this is a second hard checkpoint.
Resume in a fresh Codex conversation with `AGENTS.md`,
[Phase 14](../phases/phase-14.md), the [active ExecPlan](../plans/phase-14-execplan.md)
and targeted material from the [context map](../context-map.md). The
[benchmark index](../benchmarks/README.md) and [Session 2 analysis](../benchmarks/phase-14-session-2.md)
hold exact runs, raw evidence, comparisons, limitations and Phase 15 input.

Session 1 harness/measurement commits: `c86f4f8`, `fec1826`. Session 2 extended
harness: `4f7932e`. Application HEAD in Session 2 run snapshots was `fec1826`;
the harness was still a working-tree development version during measurement
and was committed afterward. No auction business rule or permanent runtime
setting changed. Main results used API observability enabled, k6 1.8.1,
fresh fixtures and separate read-only warm-ups.

Measured: closing storm with 138 accepted bids, one valid 90-second extension
and correct closer/winner; hot 8/16/32/64 VU steps with flattened ~84–101
HTTP/s and p95 rising to 935ms while lock p95 stayed ≤25ms at 64; matched
16-VU one-row/eight-row loop; 400/600 clean final-ten-second contender
bursts; 50/200/500 confirmed Cable subscriber steps; normal/hot repeats and
targeted duplicate burst. Every major mutation run passed its authoritative
PostgreSQL checker. Nine selected Redis projections matched PostgreSQL after
load, and fixture outbox/Sidekiq queues drained. Checker and classifier
sabotage detected controlled invalid input and restoration was verified.

The 1,000-bidder attempt launched all 1,000 VUs but hit the API process's
1,024-open-file soft limit: 28 `EMFILE` server errors and 64 HTTP timeouts.
PostgreSQL still held one bid, valid extension/closure, and 911 completed
command records versus 908 successful/expected HTTP responses. It is not a
production capacity result. The highest clean local burst observed was 600
contenders, with p95 8.81 seconds. At 500 Cable subscribers, k6 received
13,500 server invalidations; this is not universal browser delivery.

Next: reconcile benchmark provenance/completeness without rerunning successful
experiments needlessly; run full backend/static/security and frontend gates,
Compose/runtime and browser checks, hosted CI; repair failures; finish final
Phase 14 docs and adversarial review. Pool checkout and Puma admission waits
were not instrumented; the optional stable telemetry-overhead pair was not
run. Do not start Phase 15 or implement its performance candidates. Phase 14
is not complete.
