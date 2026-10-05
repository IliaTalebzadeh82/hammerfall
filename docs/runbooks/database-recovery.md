# PostgreSQL recovery and derived-state restart

PostgreSQL 18 is the auction authority. This procedure is for a declared
database-loss/PITR incident, not routine Redis or Kafka repair. Keep a durable
incident record of the recovery target, image/configuration versions, backup
identity, WAL coverage, operator and all deliberate transport resets. The local
exercise below is verified; the cloud path is a reference design only.

## Backup contract before an incident

Keep periodic physical base backups and a continuous, monitored WAL archive in
storage independent of the primary. Verify backup manifests with
`pg_verifybackup`, verify archive continuity to the intended recovery point,
and repeatedly restore to a separate cluster. Set base-backup cadence, WAL
archive lag alert and retention from a reviewed recovery objective and actual
restore measurements; this repository has no production target to justify
fixed numbers. Protect backup storage as sensitive as live PostgreSQL.
`pg_dump` can supplement logical portability checks but cannot replace the
base-backup plus WAL mechanism for point-in-time recovery.

## Freeze and choose a target

1. Stop API mutation ingress and drain/stop API writers, closer, Sidekiq,
   reconciliation scheduler, both outbox publishers and both Kafka consumers.
   Keep the old PostgreSQL and Kafka/Redis data isolated for forensic review.
   Do not allow a surviving API replica to reconnect to the restored database.
2. Establish the last trustworthy PostgreSQL base backup and continuous WAL
   range. Record a target LSN or database timestamp and why it was selected.
   Compare the target with known client acknowledgments: a command acknowledged
   after the target can be absent after restore. This is real RPO loss; a later
   same-key retry can be a new command. Escalate business reconciliation rather
   than inventing a prior result.
3. Restore the matching configuration and secret versions in a protected store:
   database access, `SECRET_KEY_BASE`, and every HMAC key ID present in the
   selected backup or any other still-restorable backup. A live-table prune does
   not justify deleting a key while older backups remain restorable. Verify
   keyring material is identical across replicas without printing it.

## Physical restore

For a self-managed PostgreSQL 18 cluster, restore a verified `pg_basebackup`
directory to **new, empty storage** with the same major PostgreSQL version.
Make the archived WAL available read-only, configure `restore_command`, set
`recovery_target_lsn` or `recovery_target_time`, create `recovery.signal`, and
start the isolated server. Use `recovery_target_action=promote` only after the
selected target is reviewed. Check recovery logs, timeline, promotion and
`pg_is_in_recovery() = false`. Do not point ordinary application traffic at it
yet. Verify `pg_verifybackup` before relying on the base backup; a successful
backup command alone is insufficient.

The repeatable local physical exercise uses a separate PostgreSQL 18.6
container, archived WAL and an isolated Redis. From the repository root, with
the normal Compose API image and network available:

```sh
scripts/recovery/phase22-pitr
```

It prints an ignored `apps/api/tmp/phase22-recovery.*` directory and target
LSN. The directory contains a generated disposable DB password and sensitive
backup/WAL; restrict access. It takes a streaming base backup, verifies it with `pg_verifybackup`,
commits T1/T2/T3, archives WAL, stops the isolated primary, restores to the
post-T2 LSN, promotes and validates. It never modifies the ordinary Compose
PostgreSQL volume. To retire **only** the isolated containers/volume after
review, set `PHASE22_WORK_DIR` to the printed path and run:

```sh
PHASE22_WORK_DIR=/absolute/printed/path PHASE22_DB_PASSWORD="$(cat /absolute/printed/path/db-password)" docker compose -f scripts/recovery/compose.yml --profile restore down -v
```

The ignored backup/WAL directory remains until an operator removes it; treat
it as sensitive database material. Do not commit or share it.

The GCP reference configures Cloud SQL backups and PITR, but no Cloud SQL
restore was run. A real deployment needs a credentialed restore to a separate
instance, backup/WAL retention and access checks, secret recovery, measured
restore time at representative size and application connectivity validation.

## Validate PostgreSQL authority before async restart

Use protected SQL/Rails access to compare the target's auction status, price,
leader, winner, reserve status, deadline, public revision, bid sequence,
private maximum, idempotency outcome and outbox rows. Check constraints and
expected migration state. Retry a retained command with the original
actor/key/payload: it must replay the historical outcome without new bids or
events. Do not put private maximum or key material in incident logs. Identify
client successes that occurred after the target separately; they are absent
from restored authority and need operator/business reconciliation.

## Resolve Kafka and outbox divergence

**Do not resume the old Kafka projection consumer against a PITR database.**
It applies any valid higher revision without consulting PostgreSQL. An old
broker may contain a T3 event while PostgreSQL has only T2; it would recreate
future Redis state. The audit consumer would also record an orphaned event as
metadata. The ordinary reconciliation scan flags an ahead key for review and
does not overwrite it. Offsets and a valid Redis digest cannot establish truth.

For a complete database PITR with the current two consumer groups, quarantine
the old broker and start a fresh isolated Kafka cluster/topic with the same
three partitions and empty group offsets. Preserve the old broker for incident
analysis. Under a reviewed maintenance change, requeue **retained domain**
outbox rows by clearing `kafka_published_at` and setting
`kafka_next_attempt_at=clock_timestamp()`; leave event IDs and immutable
snapshots intact. This deliberately republishes retained history to the fresh
broker. Restored `consumed_kafka_events` receipts deduplicate already recorded
audit effects; missing receipts can be rebuilt from retained events. Pre-Kafka
legacy rows have no domain snapshot and cannot be reconstructed as historical
events. If external consumers, unretained history or an existing broker must
be preserved, stop here for a reviewed per-group recovery plan; the current
consumer has no safe automatic filter for orphaned future events. Do not reset
offsets merely to clear lag or claim exactly-once recovery.

For the **fresh broker and fresh Redis** path only, the reviewed requeue change
can use bounded PostgreSQL ID ranges after writers are fenced. Record each
range and row count in the incident record. Replace `:low_id` and `:high_id`
with numeric bounds and execute each range as one transaction against the
**restored** database:

```sql
BEGIN;
UPDATE outbox_events
SET kafka_published_at = NULL, kafka_next_attempt_at = clock_timestamp()
WHERE id BETWEEN :low_id AND :high_id AND domain_event_type IS NOT NULL;
UPDATE outbox_events
SET published_at = NULL, next_attempt_at = clock_timestamp()
WHERE id BETWEEN :low_id AND :high_id;
COMMIT;
```

Check pending counts against retained outbox rows before starting publishers.
Choose range size for measured WAL volume and lock duration. This is a PITR
exception to the ordinary runbooks' rule against manually altering delivery
acknowledgments. It never changes revisions, event IDs or snapshots.

`published_at` acknowledges Sidekiq enqueue; `kafka_published_at` acknowledges
broker delivery. After PITR either can be pending again even if the old
transport saw the event. Redelivery is expected. `AuctionChangedJob` reads the
current revision, audit effects deduplicate by event ID, and projection writes
compare revisions. These protections do not make an ahead Kafka event safe.

## Rebuild Redis, queues and traffic

Use a fresh Redis instance for a full PITR, or preserve unrelated keys while
deleting the **entire** `hammerfall:auction-public:v2:*` namespace after
confirming the restored authority. A valid ahead key must be removed before
seeding; the revision guard correctly refuses to lower it. Run
`bin/rebuild_auction_projections` against restored PostgreSQL, compare public
revision and fields with ordinary PostgreSQL GET, and run the one-shot
reconciliation scheduler after restarting Sidekiq. Never restore a stale Redis
snapshot as auction truth.

If the Redis Sidekiq queue was discarded, notification jobs already marked
`published_at` can be lost. The reviewed batch above requeues them; then drain
the publisher. Duplicate
hints are safe. Maintenance scan jobs are reconstructible: an abandoned
PostgreSQL lease expires and a later scheduler tick restarts the bounded scan.
Inspect Retry/Dead sets if keeping old Redis; a future-revision job from the
discarded timeline must not be retried. Reset rate-limit counters mean a
temporary abuse-protection gap; PostgreSQL-backed sessions before the target
survive, while sessions created after it disappear.

Start compatible Kafka consumers and both publishers only after broker reset,
outbox review and Redis replacement/seed. Verify publisher backlog, audit
receipt counts, consumer lag, projection equality and reconciliation results.
Then resume closer/scheduler/Sidekiq and finally mutation ingress. Watch for
new bids, retries and stale browser views through PostgreSQL-backed REST.

## Recovery objectives and limits

RPO is the maximum committed data loss at the selected restore point; RTO is
the interval until useful validated service returns. Neither has a production
target or guarantee here. The local fixture's times in the Session 1 report
exclude incident diagnosis, backup discovery, secret retrieval, Kafka reset,
full async drain and traffic verification. A real RTO must measure all of them.
