# Load testing

Phase 14 is in progress. The [k6 harness](../load-tests/README.md) creates
isolated HTTP fixtures and records normal multi-auction, one-hot-auction and
duplicate-retry runs. PostgreSQL verification checks each fixture after load.
Retained [results](benchmarks/) include the exact command, local environment,
warm-up, k6 summary/log, observability snapshots and interpretation. These are
local shared-host measurements, not production capacity claims.

The closing-storm, 1,000-bidder challenge, WebSocket fanout, stepped saturation,
repeatability and final regressions remain Phase 14 work. See the active
[ExecPlan](plans/phase-14-execplan.md) for the Evidence Index and next step.
