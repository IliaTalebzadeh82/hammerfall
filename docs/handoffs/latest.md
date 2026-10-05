# Current handoff — Phase 22 Kafka recovery checkpoint

Phase 21 — COMPLETE. Phase 22 — IN PROGRESS. Phase 23 — NOT STARTED.
Updated: 2026-10-05. Read [Phase 22 spec](../phases/phase-22.md), the active
[ExecPlan](../plans/phase-22-execplan.md), and targeted recovery/operations
context. The next substantial session must finish Phase 22 operations and
closure; do not start Phase 23.

Session 1 proved PostgreSQL 18.6 physical PITR with archived WAL and
`pg_verifybackup` after T2/before T3. The restored auction was revision 4 with
policy, bid sequence, private maximum, idempotency and outbox state intact.
T2 replayed without mutation; T3 was absent despite client acknowledgment.
An ahead Redis revision 5 had to be removed before PostgreSQL seed 4. A real
old-app compatibility drill proved fixed data readable but old code accepted
a stepped bid current code rejects. Rapid-data schema rollback was guarded.
See [Session 1 evidence](../operations/phase-22-session-1.md).

Session 2's isolated Kafka milestone is verified. The old broker received and
consumed revisions 1–5; Redis reached discarded revision 5. The broker was
stopped before PITR. The restored PostgreSQL contained only revisions 1–4 and
retained three audit receipts. A distinct fresh broker received four requeued
outbox events. The audit consumer returned three duplicates and one new
effect; the projection consumer returned three stale and one duplicate.
Redis matched PostgreSQL revision 4 and public fields exactly; actual
reconciliation returned healthy; the old broker stayed stopped. Evidence:
[Kafka recovery checkpoint](../operations/phase-22-kafka-recovery.md),
[recovery runbook](../runbooks/database-recovery.md), and the ExecPlan index.
The first harness attempt exposed unrelated `db:prepare` demo seeds; using
`db:create db:migrate` made the isolated fixture deterministic.

Remaining: Sidekiq queue classification/replay, traffic fence/resume,
evidence-backed SLIs and actionable alerts, Phase 20-role secured operator
diagnostic/recovery workflow, integrated production-style game day, adversarial
review, full local regression/Compose/browser/static gates, final documentation,
commit/push and exact-SHA hosted CI. No Cloud SQL restore, managed Kafka DR,
secret-store retrieval, representative recovery volume or production RPO/RTO
is verified. The current consumer still accepts an ahead event if an old
broker is accidentally resumed; strict broker quarantine is mandatory.
