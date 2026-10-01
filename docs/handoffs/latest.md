# Current handoff — Phase 15 complete; Phase 16 not started

Updated: 2026-10-02. Phase 15 Performance Engineering is complete. Begin
Phase 16 only on an explicit request, in a fresh session with
[AGENTS.md](../../AGENTS.md), the [Phase 16 specification](../phases/phase-16.md)
and targeted architecture context. Do not treat Phase 15's local benchmark
numbers as production capacity or chaos evidence.

The [Phase 15 final review](../benchmarks/phase-15-final.md) is the concise
causal model and decision record; [Sessions 1 and 2](../benchmarks/README.md)
retain measurements. The [completed ExecPlan](../plans/phase-15-execplan.md)
and [gate index](../benchmarks/phase-15-final-gates/README.md) locate tests,
runtime/browser checks and hosted [CI run 36941725862](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36941725862), whose API, web and Compose jobs all passed.

Under local hot load, Puma admission backlog was substantial; baseline DB
checkout and auction-lock wait were small. Development file checking cost CPU,
but disabling request reloading did not reliably fix the HTTP tail. Five Puma
threads moved waiting into the DB pool; pool five removed that wait without
repeatable end-to-end benefit. Both tuning changes were rejected. OTel was
retained; no auction, publisher, FD or production tuning was adopted. Ordinary
local API runtime is development reloading on, three request threads/pool
three, diagnostics and CPU profiling off. This checkout's ignored `.env` pins
OTel on for the measured local stack; the Compose default remains off unless
configured.

Exact per-request pre-Rack time, production worker/thread/pool sizing,
long-term memory behavior and larger WebSocket capacity remain unmeasured.
The 1,024 soft FD ceiling explained the failed local 1,000-contender burst;
no short-run FD or memory leak was demonstrated. Preserve PostgreSQL auction
authority, command identity, privacy, outbox and derived-state recovery when
Phase 16 is requested.
