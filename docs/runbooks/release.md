# Hammerfall release and rollback

Use [the compatibility policy](../operations/release-compatibility.md) for the
exact migration/worker matrix and [database recovery](database-recovery.md)
for a failed database change. This is an operator procedure, not an automated
production deploy system.

## Preflight

1. Record Git SHA, built API/web image **digests**, configuration/keyring
   version IDs, expected `schema_migrations` versions and supported v1/v2
   event shapes. Test and promote the same immutable digest. CI currently
   tests source/Compose builds; registry promotion is not implemented.
2. Check PostgreSQL backup, WAL coverage and a recent restore exercise.
   Confirm every retained idempotency key ID in the live database **and every
   still-restorable backup** has recoverable material. Confirm all replicas
   receive the same keyring; never print it.
3. Inspect migration class, data prerequisites, lock/connection budget,
   old/new app matrix, reader/worker compatibility and rollback point. Query
   `schema_migrations`; do not infer state only from a file name. Check outbox
   backlog, Kafka lag, Sidekiq Retry/Dead and reconciliation drift before
   starting; record the baseline.

In local Compose, inspect migration and role state with
`docker compose exec -T api bin/rails db:migrate:status` and
`docker compose ps`. The ordinary API startup runs `db:prepare`; do not start
an unreviewed new image while old writers are active. The GKE reference has a
suspended `db-prepare` Job for an explicit migration step, but no cloud release
pipeline has been exercised.

## Compatible expansion

For a migration proven compatible with current rows/writers, apply the schema
expansion first, deploy event readers/consumers able to parse both retained and
new payloads, then deploy API/web writers and workers using immutable digests.
Observe health `/ready`, ordinary PostgreSQL GET, an authenticated idempotent
command/replay, outbox drains, audit receipts, projection revisions and
reconciliation. Contract schema only in a later release after old code, jobs
and retained messages are gone.

## Phase 21 policy release (coordinated drain)

1. Stop new mutation ingress. Drain in-flight old API requests, closer,
   publishers, audit/projection consumers, Sidekiq and scheduler. Verify no
   old bid writer remains; old code accepts an invalid stepped amount.
2. Apply the Phase 21 migrations and validate them. Upgrade/restart the v1/v2
   Kafka readers and v2 projection/reconciler before any v2 event or reserve
   writer. Keep old group offsets; consumers upgrade individually, so no old
   consumer may remain when writers start.
3. Start current compatible workers and API images, then enable policy
   creation/writes. Verify regular and rapid deadlines, reserve-unsold result,
   idempotency replay, v2 event publication/audit, v2 Redis seed and lag.
   Resume ingress only when PostgreSQL and async checks pass.

The HMAC migration is a separate coordinated drain: old executor code does
not take the advisory lock or read new HMAC rows. Distribute a byte-identical
keyring, stop old executors, migrate, then start new executors. Keep previous
keys until no retained row in **any recoverable backup** requires them.

## Failed rollout decision

If migration succeeds but the new image fails readiness, keep traffic frozen.
Inspect whether new policy rows/events or HMAC outcomes were written. With only
fixed/regular/no-reserve/v1 data and a proven old image, roll back the app
image while retaining the expanded schema, then verify an old-safe command
and publisher/consumer behavior. Once stepped, reserve, rapid, v2 or HMAC
data exists, old code is unsafe: keep writers stopped and forward-fix with a
compatible image. Do not run `db:rollback` or reset Kafka offsets to make a
deployment appear healthy. A database restore is an incident with RPO loss,
not a routine application rollback.

If a worker fails mid-deploy, keep new writers disabled until old consumers
have drained and restarted with the compatible codec. Restarting Sidekiq or
publishers can duplicate hints/events; verify outbox IDs/revisions, audit
receipts and projection guards. After any successful rollout, run a one-shot
reconciliation sweep and compare representative public states with
PostgreSQL. Record actual health, lag and rollback decision in the release
record. No zero-downtime guarantee is claimed for these drains.
