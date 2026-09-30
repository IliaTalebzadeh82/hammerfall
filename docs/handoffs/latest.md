# Current handoff — Phase 12 primary implementation checkpoint

Updated: 2026-10-01. Phase 12 reconciliation is active, not complete. Begin a fresh session from [the Phase 12 ExecPlan](../plans/phase-12-execplan.md), [Phase 12 specification](../phases/phase-12.md) and `AGENTS.md`. Phase 13 has not started.

PostgreSQL remains authoritative. The new checker compares the current auction public revision and public fields to a validated Redis projection. It seeds missing or lower-revision keys through the existing atomic Redis write. Equal-revision mismatches, malformed keys and keys ahead of a fresh PostgreSQL row require operator review. The scheduler enqueues a separate bounded projection job alongside the existing read-only PostgreSQL sweep; neither participates in bidding. Per-batch structured logs report drift, repair, repair-failure, attempt, unavailable and review counts.

Focused integration tests using local PostgreSQL/Redis passed: 14 examples, 0 failures, seed 59735; changed-file RuboCop passed, 5 files/0 offenses. The live corruption/outage/concurrency/crash/sabotage campaign, final regression, runtime checks, ADR/runbook and other documentation remain. The ExecPlan records exact changed paths, decisions, evidence and next work. No Phase 12 completion or production freshness guarantee is claimed.
