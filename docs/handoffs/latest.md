# Current handoff — Phase 22 Session 1 checkpoint

Phase 21 — COMPLETE. Phase 22 — IN PROGRESS. Phase 23 — NOT STARTED.
Updated: 2026-10-05. Start the next substantial session with
[Phase 22 spec](../phases/phase-22.md), the active
[ExecPlan](../plans/phase-22-execplan.md), and targeted recovery/release
context. Session 1 completed the durability and release milestone; Session 2
owns operational policy, an integrated game day and Phase 22 closure.

A dedicated PostgreSQL 18.6 cluster ran `pg_basebackup` plus WAL archiving,
passed `pg_verifybackup`, and restored to LSN `0/400C3D0` after T2 but before
T3. The rapid, stepped, reserved auction recovered at revision 4 with bid
sequence, private maximum, idempotency and outbox state intact. The retained
T2 command replayed without mutation. Isolated Redis held discarded revision
5; the lower revision seed was refused until the derived key was removed and
rebuilt from PostgreSQL. Local backup/verify, restore startup, validation and
Redis rebuild steps took 1/2/1/3 seconds respectively; no production RPO/RTO
is claimed. See [Session 1 report](../operations/phase-22-session-1.md) and
[database recovery runbook](../runbooks/database-recovery.md).

A detached real Phase 20 `6c38b59` app wrote fixed data on expanded Phase 21
schema and current code read it. On a stepped row the old writer accepted a
36,000-cent bid in a rolled-back transaction while current code required
37,000. A rapid-data `db:rollback STEP=1` raised and preserved the schema.
The [compatibility matrix](../operations/release-compatibility.md) and
[release runbook](../runbooks/release.md) require reader-first v2 rollout and
old-writer drain. Focused backend: 73 examples, 0 failures, 1 opt-in pending;
fixture RuboCop, shellcheck and Bash syntax passed. The ExecPlan Evidence
Index points to ignored local logs.

Critical recovery boundary: the current Kafka projection consumer accepts a
valid higher revision without a PostgreSQL check. A broker ahead of restored
PostgreSQL must remain quarantined; clearing Redis alone is insufficient. The
fresh-broker/requeue design is documented but has **not** been exercised.
Session 2 should test that integrated path and complete SLIs/SLOs, alerts,
secured operator workflow, ownership, game day and final regression. Cloud SQL
restore, secret-store retrieval, representative volume and full traffic
freeze/resume are unverified. Do not start Phase 23.
