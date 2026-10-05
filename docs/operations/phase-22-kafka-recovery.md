# Phase 22 Session 2 checkpoint — Kafka-ahead PITR recovery

Status: isolated Kafka/outbox/Redis recovery milestone verified locally on
2026-10-05. Phase 22 remains **in progress**. This is not the integrated
production-style game day or a production DR claim.

## Threat and procedure

The old broker carried a valid revision 5 event after PostgreSQL PITR selected
revision 4. The projection consumer accepts a higher valid revision without
checking PostgreSQL. Resuming that broker after clearing Redis could therefore
resurrect discarded state. The exercised sequence fenced the old broker,
restored PostgreSQL, removed and seeded the ahead Redis projection, started a
fresh broker with a distinct endpoint and empty offsets, requeued retained
PostgreSQL outbox intents, replayed them through the actual Kafka publisher
and both consumers, then reconciled.

Command: `PHASE22_KAFKA_DRILL=1 scripts/recovery/phase22-pitr`. It uses the
normal Compose API image/network but dedicated PostgreSQL, Redis and two Kafka
containers/volumes. It does not alter ordinary development Kafka. The isolated
database is migrated without demo seeds. The fixture asserts broker endpoint
identity and that the old broker remains stopped at the end. The ignored log
is `apps/api/tmp/phase22-kafka-drill.log`; sensitive backup/WAL artifacts are
in the ignored `apps/api/tmp/phase22-recovery.X5ojXW` directory. Neither should
be committed or shared raw.

## Observed sequence and evidence index

| Step | Observed result | Evidence |
| --- | --- | --- |
| Base backup and target | `pg_verifybackup` passed; after T2 target LSN `0/6003940`; T3 committed later | Drill log `backup successfully verified`, `recovery_target_lsn` |
| Old Kafka | Revisions 1–3 consumed before target; revisions 4–5 published and consumed afterward; consumed record offsets 0–4 | `kafka_old_before`, `kafka_old_future`; latter reports Redis revision 5 |
| Fence and PITR | Old broker stopped before restore; restored PostgreSQL revision 4; T1/T2 and retained idempotency survived, T3 absent | `old_kafka_quarantined=stopped`, `verify` |
| Redis ahead/rebuild | Revision 4 seed returned `stale` while Redis held 5; deleting one derived key and seeding returned exact revision 4 | `seed`, `delete_projection`, `seed` |
| Authoritative requeue | Restored outbox revisions 1–4 only; 1–3 had old Kafka acknowledgments and were requeued with revision 4; immutable event IDs/snapshots remained | `verify`, `kafka_requeue` (4 rows, IDs 1–4) |
| Fresh broker | Four events published to separate `phase22-fresh-kafka:9092`; no revision 5 was published | `kafka_fresh_replay` and event logs |
| Audit duplicate handling | Restored receipts for 1–3 returned `duplicate`; missing revision 4 returned `next`; final receipt and audit counts both 4 | `kafka_fresh_replay` |
| Projection duplicate handling | Pre-replay PostgreSQL seed at 4; event revisions 1–3 returned `stale`, 4 returned `duplicate`; Redis revision 4 matched presenter fields exactly | `kafka_fresh_replay` |
| Reconciliation and quarantine | Actual `AuctionProjectionReconciler#check` returned `healthy`; old broker still stopped | `kafka_fresh_replay`, `old_kafka_still_quarantined=true` |

The recovered authoritative auction was active, rapid/stepped, current price
35,000 cents, reserve not met, revision 4, two ordered bids, and no winner.
The private maximum was asserted without printing it. Retained T2 replay made
no new bid/outbox row. T3's acknowledged client success was absent after the
selected target. This is nonzero RPO; retry protection applies only to
surviving records.

The old and fresh brokers deliberately reused the application consumer group
names. They had independent logs and offset stores. Reusing an old broker or
resetting its offsets would not have been safe. Redis seed before replay made
the restored current state available first; legitimate older events then
could not regress it. The fresh broker test proves this local procedure, not
managed Kafka DR or safe operation with unretained/external consumers.

## Decision record and remaining work

- Quarantine old Kafka because it contains a post-target event that the
  current projection consumer would accept.
- Clear only the derived projection namespace because its valid higher
  revision blocks a lower PostgreSQL seed.
- Republish immutable retained outbox snapshots because PostgreSQL is the
  authority for publication intent. Rewound acknowledgments imply at-least-once
  delivery; receipt and revision guards absorbed observed duplicates.
- Keep the expanded schema. The separate Session 1 compatibility drill proved
  that an old writer can boot yet write behavior that current policy rejects.

Still required for Phase 22: Sidekiq queue inspection/classification, explicit
application traffic fence and resume, secured operator workflow, SLIs/alerts,
integrated game day, adversarial review, final regression and hosted CI. No
production RPO/RTO, representative data-volume recovery time, Cloud SQL
restore, secret-store retrieval or managed Kafka recovery is established.
