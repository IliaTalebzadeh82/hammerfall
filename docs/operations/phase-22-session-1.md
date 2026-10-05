# Phase 22 Session 1 — recovery and release evidence

Status: Session 1 milestone verified; Phase 22 in progress. This report distinguishes verified local exercises from
the untested cloud/operational design. PostgreSQL alone owns auction outcomes.

## Durable state inventory

| State | Store | Authority / recovery source | Backup decision |
| --- | --- | --- | --- |
| Auctions, bid sequence/history, private maxima, reserve and deadline | PostgreSQL | Auction authority; cannot be rebuilt from public transports | Physical backup + WAL mandatory |
| Completed command outcomes and digest metadata | PostgreSQL | Retry authority during physical retention; raw key is not stored | Included; retain matching HMAC versions |
| Outbox event IDs, snapshots, retry and delivery acknowledgments | PostgreSQL | Publication intent for retained public revisions | Included; replay can duplicate |
| Users, credentials and sessions | PostgreSQL | Security state; post-target sessions disappear | Included; protect as sensitive |
| Kafka consumer receipts and audit entries | PostgreSQL | Durable dedupe/public audit metadata, not bid authority | Included; may need rebuild from retained outbox |
| Reconciliation leases | PostgreSQL | Operational scan ownership, expires/reclaims | Included incidentally; not auction authority |
| Kafka events and group offsets | Single-node local Kafka | Async transport/history; may be ahead of PITR or lack old history | Quarantine on PITR; fresh broker/replay retained outbox is design, not yet exercised |
| Redis public projection | Redis | Derived from current PostgreSQL | Rebuild; do not use stale backup as authority |
| Sidekiq notification/maintenance queues and retry/dead sets | Redis | Hints and scans; notifications can be requeued from retained outbox, scans from leases/scheduler | Inspect or rebuild; not auction authority |
| Rate-limit counters | Redis | Disposable protection state | Reset has abuse-control impact |
| HMAC keyring, `SECRET_KEY_BASE`, DB/Kafka/Redis credentials and trust roots | Protected config/secret store | Required for replay, session crypto or connectivity | Independent protected backup/version recovery; never commit payloads |

Auction correctness recovery means restoring PostgreSQL and its keyring. Service
continuity additionally needs transport/worker and ingress recovery. Derived
state recovery means rebuilding Redis and reconciling it against PostgreSQL.

## Physical PITR exercise

`scripts/recovery/phase22-pitr` used PostgreSQL 18.6 and an isolated cluster.
`pg_basebackup -X stream` produced a physical base backup, then
`pg_verifybackup` succeeded. The fixture had authenticated users, a rapid
stepped auction with hidden reserve, credentialed actors, a private maximum, accepted bids,
completed HMAC idempotency records and v2 public outbox snapshots. Base backup
followed activation (revision 2). T1 set a maximum (revision 3); T2 accepted a
bid (revision 4); T3 accepted another bid (revision 5). Target LSN after T2:
`0/400C3D0`. The isolated primary was stopped and archived WAL replayed to
that LSN; recovered PostgreSQL promoted. No ordinary Compose DB volume was
changed.

Recovered auction 4 was active, price 35,000 cents, revision 4, no winner,
reserve not met, rapid closing, stepped increments and the T2 leader/deadline.
Two bid rows had sequences 1–2. The fixture asserted the private maximum
inside PostgreSQL without logging its value. Two retained command records and
four outbox revisions survived; T3's bid/command/revision did not. All four
outbox rows were pending on both publisher paths. Repeating T2 with the same
actor/key/payload returned the stored 201 outcome without a new bid/outbox
row. The client that saw T3 success before disaster would disagree with this
restored authority; a later retry can execute anew. This is nonzero RPO, not
idempotency failure.

An isolated Redis was seeded with the discarded T3 revision 5 before restore.
A PostgreSQL seed at restored revision 4 returned `stale` and left revision 5.
Deleting only that projection key and seeding again produced revision 4. This
proves why a PITR runbook must clear ahead derived state. It does not exercise
a live Kafka-ahead record. Source review shows the projection consumer accepts
valid higher revisions without a PostgreSQL check, so the old broker cannot be
resumed blindly; see the [recovery runbook](../runbooks/database-recovery.md).

Observed local times from the final successful run: base backup plus verification
1 second; restored database startup/promotion 2 seconds; domain verification
and replay 1 second; Redis key delete/reseed 3 seconds. These coarse wall-clock
figures exclude setup, diagnosis, Kafka reset, secret retrieval and traffic
resumption. They are not a production RTO. No production RPO/RTO is set.

## Release compatibility exercise

With `PHASE22_WORK_DIR` set to the printed recovery directory, rerun
`scripts/recovery/phase22-compatibility` against the isolated recovered DB.
The actual pre-Phase-21 application at `6c38b59` ran in a detached temporary
worktree against the isolated recovered **new schema**. It created and bid on
a fixed, regular auction; current code then read that auction with `fixed`,
`regular`, `reserve_status=none` and one bid. This proves one additive-schema
case, not general rolling compatibility.

On the recovered stepped fixture at 35,000 cents, the old code calculated a
36,000-cent minimum and accepted that bid inside an explicit outer transaction
which was rolled back. Current code calculated 37,000 cents and rejected the
same bid with `bid_too_low`; revision remained 4. This proves old bid writers
must drain before stepped rows become writable. The old Kafka v1 codec also
rejects v2 event types; readers must upgrade before v2 writers emit. With rapid
rows and closing-policy events present, `db:rollback STEP=1` raised
`ActiveRecord::IrreversibleMigration`; the column and schema migration record
remained intact. A failed new app rollout after enabling Phase 21 policy data
therefore requires a forward fix or compatible new image, not Phase 20 rollback.
The representative failed release preflight used an unavailable HMAC keyring
path: current code rejected it. With stepped/rapid data already present, the
old image was demonstrably unsafe, so the recovery choice is a corrected
keyring or compatible forward image while writers stay fenced.

The [release compatibility policy](release-compatibility.md) and
[release runbook](../runbooks/release.md) contain the matrix and sequence.

## Limits and next work

No Kafka cluster reset/republication, Cloud SQL restore, representative data
volume, secret-store retrieval or full traffic freeze/resume was exercised.
The local drill's requeue/rebuild design needs an integrated Session 2 game day.
No paid cloud resource was created. Session 2 owns SLOs, alerts, operator
workflow, integrated game day and final Phase 22 closure.
