# Current handoff — Phase 15 Performance Engineering in progress

Updated: 2026-10-01. Phase 14 is complete; Phase 15 Sessions 1 and 2 have
reached the second hard checkpoint. Phase 16 has not begun. Resume with the
[Phase 15 ExecPlan](../plans/phase-15-execplan.md), [phase specification](../phases/phase-15.md)
and [Session 2 report](../benchmarks/phase-15-session-2.md). The
[Session 1 profile](../benchmarks/phase-15-session-1.md) remains available for
specific baseline evidence.

Session 1 established Puma admission backlog at 64 hot VUs (median 58 with
three request threads), DB checkout ≤1 ms with no pool wait, auction-lock p95
≤10 ms, and development file checking at 13.3% inclusive CPU samples. Exact
per-request pre-Rack delay is unavailable. No query/proxy, FD leak or
publisher bottleneck was demonstrated.

Session 2 ran 26 additional 64-VU hot loads. Diagnostic hooks showed no
repeatable material overhead beyond shared-host noise. An isolated
development reloading comparison produced 166–179 HTTP/s and 2.67–2.80
accepted mutations/s with reloading disabled versus 146–158 HTTP/s and
2.28–2.49 accepted/s with it enabled. The cleaner CPU profile reduced
`FileUpdateChecker#updated?` to 2.9% inclusive, with remaining development
migration checks. Tail latency and Puma backlog did not reliably improve.
This is a local development-runtime effect, not a production capacity claim.

API telemetry off produced 184–211 HTTP/s versus 159–179/s with telemetry
on in the cleaner window, but OTel remains enabled for operational visibility.
Five Puma threads with pool three produced ~2,300 blocking pool waits per
run and lower useful work. Pool five removed waits, added two PostgreSQL
sessions and did not improve useful work or tail latency. Both tuning
experiments were rejected; their temporary configuration overrides were
removed. A later restored three-thread baseline was slower than the earlier
window, confirming substantial host/service drift. No auction, publisher,
FD-limit or permanent performance tuning was adopted.

All 26 new hot runs had zero unexpected HTTP outcomes and passed the
authoritative PostgreSQL checker. The default API was restored healthy with
ordinary development reloading, three threads/pool three, OTel on and
diagnostics off. An opt-in development reloading switch and a report-format
fix remain. Capture no longer writes an unnecessary duplicate-key digest;
retained Phase 15 snapshots were sanitized. Focused observability RSpec:
15 examples, zero failures; Python/Ruby syntax and diff checks passed.

Next session: final performance synthesis, broad backend/frontend/security,
Compose/browser and hosted CI gates, final docs and adversarial review. Repeat
load only for a concrete unresolved decision. Do not start Phase 16.
