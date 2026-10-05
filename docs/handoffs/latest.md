# Current handoff — Phase 22 operations implementation checkpoint

Phase 21 — COMPLETE. Phase 22 — IN PROGRESS. Phase 23 — NOT STARTED.
Updated: 2026-10-05. Read the [Phase 22 spec](../phases/phase-22.md), active
[ExecPlan](../plans/phase-22-execplan.md), and targeted recovery/operations
context. The next substantial session owns the integrated game day and final
closure; do not start Phase 23.

Session 1 proved PostgreSQL 18.6 physical PITR with archived WAL and
`pg_verifybackup` after T2/before T3. Restored revision 4 retained policy,
bids, private maximum, idempotency and outbox; T2 replayed without mutation,
T3 was absent despite client acknowledgment. Ahead Redis revision 5 was
removed before seeding revision 4. A real old-app drill exposed an unsafe
stepped-bid writer and guarded rapid-data rollback. See [Session 1](../operations/phase-22-session-1.md).

The isolated Kafka drill consumed old revisions 1–5, quarantined that broker,
restored PostgreSQL to revision 4, requeued retained outbox 1–4 to a fresh
broker, and observed audit duplicates ×3/one new effect. Redis matched
PostgreSQL and reconciliation was healthy. See [Kafka checkpoint](../operations/phase-22-kafka-recovery.md).

This operations implementation milestone classified all three Sidekiq jobs:
notifications and scans are regenerable operational work; no accepted auction
command exists only in Sidekiq. A `RECOVERY_FENCE=true` API guard returns
controlled 503 for versioned reads and writes on both configured Compose
replicas, but real ingress isolation and stopped writers remain required.
Four Prometheus rules cover old outbox age, projection review, mutation 5xx
and observed close lag; production SLO/RPO/RTO remain unset. An internal
operator API is disabled by default, reuses the Phase 20 role/session/CSRF
boundary, returns bounded diagnostics, repairs only one safe public projection
and records a PostgreSQL actor/target/result/time audit row. See the
[operations report](../operations/phase-22-final.md) and affected runbooks.

Focused evidence: seven request examples/zero failures (seed 58571);
operator-audit migration rollback/reapply; targeted RuboCop and Zeitwerk;
Prometheus config/four-rule syntax, Compose config and diff whitespace all
passed. The operator/fence and alert behavior have **not** yet had a live
game-day proof. The first focused test saw leftover Redis state from a reused
test auction ID; setup/cleanup repaired it. A changed applied test migration
required resetting that isolated test table before a clean redo; no domain
failure was hidden. Evidence and exact commands are in the ExecPlan.

Next: extend/run one isolated integrated game day using the existing Kafka
PITR harness. Inspect Sidekiq queue/Retry/Dead; prove a real fenced mutation
returns 503 without a write; observe an adopted alert healthy→firing→cleared;
restore, converge and use operator diagnostics; verify T2 replay and absent T3;
record timeline and release decision. Then adversarial review, full backend,
frontend, static, ordinary Compose and browser gates, final docs, closure
commit/push and hosted CI on the **exact closure SHA**. Do not claim Phase 22
complete before these pass. Cloud SQL restore, managed Kafka DR, secret-store
retrieval, representative volume and production RPO/RTO remain unverified.
