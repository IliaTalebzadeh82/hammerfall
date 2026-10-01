# Current handoff — Phase 14 Load Testing complete

Updated: 2026-10-01. Phase 14 is complete; Phase 15 has not begun and needs an
explicit request. The [Phase 14 ExecPlan](../plans/phase-14-execplan.md),
[final review](../benchmarks/phase-14-final.md), [benchmark index](../benchmarks/README.md)
and [progress](../progress.md) hold durable implementation and verification
state. Use the [context map](../context-map.md) to route any next phase work.

The pinned k6 harness covered normal, one-hot-auction, closing storm,
duplicate, final-ten-second challenge and Action Cable fanout scenarios.
Every major retained mutation run passed authoritative PostgreSQL verification.
The highest clean local final-ten burst observed was 600 contenders. All 1,000
VUs launched in the larger attempt, but the API's 1,024-open-file soft limit
produced 28 server errors and 64 timeouts; ambiguous outcomes were reconciled
against PostgreSQL. These are short shared-host observations, not production
capacity or an SLO. No auction business rule or permanent runtime tuning
changed.

At 64 hot VUs HTTP p95 reached 935 ms, while measured auction-lock p95 was
in a ≤25 ms histogram bucket. Puma admission and DB checkout wait remain
unmeasured; the stable telemetry overhead pair was not run. Eight rows
accepted more bids than one at the same 16-VU loop, with a changed outcome
mix. Sampled outbox backlog drained, nine selected Redis projections matched
PostgreSQL, and 50/200/500 k6 Cable subscriber steps received server
invalidation hints. The Session 2 analysis classifies Phase 15 investigation
candidates by measured evidence, not presumed bottlenecks.

Final local regression passed 439 backend examples (4 expected pending), 73
frontend tests, static/security/build gates, Compose/runtime smokes and seven
real Chrome scenarios. Native test Redis was isolated to DB 15 after the first
full run collided with live Compose projection keys on DB 0. Hosted
[GitHub Actions run 36881034875](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36881034875)
on `752fe85` passed API, web and Compose jobs. The final closure commit is
only documentation. See [gate logs](../benchmarks/phase-14-final-gates/README.md)
for exact commands, the initial failure and successful rerun.
