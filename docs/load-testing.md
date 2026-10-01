# Load testing

Phase 14 local experiments and regression are complete; hosted CI is pending.
The [k6 harness](../load-tests/README.md) creates
isolated HTTP fixtures and records normal, hot, distributed-auction, closing,
duplicate, final-ten-second challenge and Action Cable fanout runs.
PostgreSQL verification checks each mutation fixture after load.
Retained [results](benchmarks/) include the exact command, local environment,
warm-up, k6 summary/log, observability snapshots and interpretation. These are
local shared-host measurements, not production capacity claims.

The [Session 2 analysis](benchmarks/phase-14-session-2.md) compares stepped
load, closing behavior, 400/600/1,000 contender bursts, 50/200/500 socket
steps, repeatability, telemetry and recovery. The 1,000-bidder attempt reached
the API container's file-descriptor limit, so it establishes no production
capacity. The [final evidence review](benchmarks/phase-14-final.md) records
the local regression, security, Compose and browser gates and remaining
limits. See the [ExecPlan](plans/phase-14-execplan.md) for the Evidence Index.
No production capacity or SLO was established; Phase 15 has not begun.
