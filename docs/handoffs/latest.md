# Current handoff — Phase 15 Performance Engineering in progress

Updated: 2026-10-01. Phase 14 is complete. Phase 15 Session 1 profiled the
missing latency boundaries and is at a hard checkpoint. Resume with the
[Phase 15 ExecPlan](../plans/phase-15-execplan.md), [phase specification](../phases/phase-15.md)
and [profiling report](../benchmarks/phase-15-session-1.md); use the
[context map](../context-map.md) for targeted source. Phase 16 has not begun.

Opt-in instrumentation now exposes Puma 8.0.2 backlog/thread stats through
a private local socket, Active Record checkout and blocking pool wait, and
bounded CPU/GC, query and FD profiles. No Puma, DB-pool, FD, auction rule or
publisher tuning was adopted. In a 64-VU hot run, Puma backlog median was 58
with three request threads at capacity; all 5,133 observed DB checkouts were
in the ≤1 ms bucket and no blocking pool wait was recorded. Auction-lock
p95 was ≤10 ms against HTTP p95 782 ms. Exact per-request pre-Rack time is
still unavailable, so the admission contribution is supported by queue
evidence rather than a direct latency percentile.

StackProf found development file checking at 13.3% inclusive CPU samples;
short real-PostgreSQL query probes found no large warm SQL hotspot. At 200
Cable subscribers, 202 of 226 peak API FDs were HTTP sockets, returning
from 20 before to 23 after load. This supports ordinary socket pressure at
the prior 1,024-FD failure without proving no slow leak. All three retained
mutation-run PostgreSQL checkers passed; focused 51 RSpec examples and
targeted RuboCop passed. The report links raw profiles and exact commands.

Next: repeat same-build diagnostic-on/off hot baselines, then test one Puma
concurrency variable with DB pool fixed if the controlled evidence supports
it. Continue memory/FD investigation and resource economics, repeat meaningful
improvements with authoritative correctness checks, then complete broad
regression, Compose/browser, hosted CI, final review and documentation.
Current local runs are shared-host comparative evidence, not capacity claims.
