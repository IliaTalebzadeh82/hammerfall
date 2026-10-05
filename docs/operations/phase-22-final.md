# Phase 22 final operations evidence

Status: **in progress**. The [physical PITR and release exercise](phase-22-session-1.md),
[Kafka timeline exercise](phase-22-kafka-recovery.md), and integrated local game
day below are verified. Final regression and hosted CI remain.

## Sidekiq authority and recovery policy

The only job classes are `AuctionChangedJob`, `ReconciliationSweepJob`, and
`AuctionProjectionReconciliationJob`; the configured queues are `notifications`
and `maintenance`. No accepted auction command depends on a queued job for
durable correctness. Auction mutations and outbox intent commit in PostgreSQL.
Sidekiq holds hints and bounded comparison work.

| Job | Source and effect | Recovery classification | Retry/dead decision |
| --- | --- | --- | --- |
| `AuctionChangedJob` | PostgreSQL outbox ID/revision; reads current PostgreSQL revision and broadcasts a REST invalidation hint | **REGENERATE** retained intents by reviewed outbox requeue; duplicate hints are safe | Retry individually only when requested revision survives PostgreSQL and Cable dependency is restored. Discard future-timeline revision. A lost hint leaves REST authoritative but may leave a connected browser stale until its next refresh. |
| `ReconciliationSweepJob` | PostgreSQL lease/cursor; reads PostgreSQL bids and auctions, logs drift, never repairs | **REGENERATE** from scheduler after lease expiry | Discard obsolete cursor/token from old timeline. Investigate logged PostgreSQL drift; never replay an old token to repair truth. |
| `AuctionProjectionReconciliationJob` | PostgreSQL lease/cursor and current PostgreSQL row; compares/repairs only disposable Redis public state | **REGENERATE** from scheduler after lease expiry | Discard obsolete cursor/token; on retry/dead inspect current PostgreSQL and Redis, then let lease/scheduler restart. Preserve ahead/conflicting/corrupt keys for review. |

All job classes use at most five Sidekiq retries. Inspect queue, Retry and Dead
sets before replacing Redis; do not bulk retry. The live exercise found five
`AuctionChangedJob` entries, one of each maintenance job, and zero Retry, Dead
and Scheduled entries. After a full PITR, old Redis
queue, retry and dead entries are forensic data, not a replay source. Requeue
retained outbox notification intents and let expired PostgreSQL leases be
reclaimed by the scheduler. Verify the new queue drains, REST state is current,
and reconciliation reaches healthy. The live exercise discarded the old Redis
queue, regenerated four retained notification hints and both scans, and
observed both queues drain with zero Retry/Dead entries. The old revision-5
hint was not replayed.

## Recovery traffic fence and safe resume

The incident operator blocks **all** external API and web traffic at ingress
and stops/drains every API writer, closer, scheduler, Sidekiq worker, publisher
and Kafka consumer before choosing a PITR target. Reads are also fenced:
PostgreSQL can be unavailable during restore, while Redis and Kafka can show
a later, discarded timeline. The `RECOVERY_FENCE=true` Rails API setting returns
JSON 503 `recovery_in_progress` for versioned API reads and writes, with
`Retry-After: 60` and `Cache-Control: no-store`; it is a local defensive guard,
not a distributed lock or a substitute for verified ingress isolation and
stopped writers. Both Compose API replicas receive the setting. Health probes
remain available. The game day proved an authenticated mutation through
isolated ingress and directly against both API replicas received 503,
`Retry-After: 60` and `Cache-Control: no-store`; a versioned read also received
503. Bid, idempotency and outbox counts and auction revision did not change.
The separately bound loopback operator process had its fence off for authorized
recovery work while the public replicas remained fenced.

Resume only after: PostgreSQL target/secret/keyring validation; old broker
quarantine and distinct fresh endpoint; Redis projection namespace removal and
PostgreSQL seed; reviewed retained-outbox requeue and fresh broker publication;
audit/projection consumers and dedupe verification; Sidekiq/scheduler restart
and reconciliation; ordinary PostgreSQL and derived reads agreeing; compatible
API version/readiness and one controlled user mutation. Remove ingress fence
last. Never reconnect the old Kafka endpoint or reuse an ahead Redis snapshot.

## Service indicators and policy

Production SLOs, RPO and RTO are **unset**. The four alert thresholds below are
**provisional operating thresholds** for this local stack, not contractual
targets. The local 15-second scrape/evaluation cycle and one-second closer
poll are known; representative production traffic, data volume, cloud latency,
managed Kafka, Cloud SQL restore time, secret retrieval and real on-call
response are not measured.

| Indicator | Interpretation | Current threshold / limit |
| --- | --- | --- |
| Auction mutation 5xx count | Server/infrastructure errors; 2xx successful commands and valid 4xx business rejections are separate | Five 5xx in a rolling five minutes, then sustained one minute. Low-traffic detection is deliberately coarse. |
| Oldest unpublished outbox age, by channel | Committed intent waiting for Sidekiq enqueue or Kafka broker acknowledgment; not consumer completion | Over 90 seconds for two minutes. The existing retry cap is 300 seconds; this detects a growing outage before that cap. Gauge is sampled by publishers, so a dead publisher requires process health checks. |
| Projection operator-review count | Conflicting, ahead, corrupt or failed repair observed by scheduled reconciliation | Any increase in five minutes sustained one minute. A missing scan means no new observation; check scheduler/lease health. Ordinary auto-repaired drift does not page. |
| Closed-auction delay | Actual DB-clock `closed_at - ends_at` on successful close | Any observed delay over ten seconds in ten minutes sustained one minute. Ten seconds is a local diagnostic margin over the one-second poll, not a closure guarantee; a dead closer emits no sample. |

Kafka broker consumer lag remains a diagnostic SLI, not a firing alert: the
current gauge updates only after successful commits, so an idle/stopped
consumer can leave a stale healthy sample. Confirm group offsets with the
Kafka runbook. DB checkout wait and pool gauges require the Phase 15 opt-in
diagnostics and are not always available; no default alert uses them. Public
revision and Redis revision are per-auction diagnostic checks, not a full-table
Prometheus scrape. Exactly one winner and legal bid ordering are invariants,
not availability SLOs.

## Severity and ownership

| Severity | Trigger and response ownership |
| --- | --- |
| SEV-1 | PostgreSQL authority, bid ordering, winner/durability, or a PITR timeline breach threatened. Database recovery owner leads; auction-domain owner validates truth. Fence traffic. |
| SEV-2 | Auction mutations unavailable or materially delayed closure while authority remains trusted. API or auction operator leads, database operator assists. |
| SEV-3 | Kafka/Sidekiq delivery, Redis projection, or reconciliation degraded while PostgreSQL authority and mutations remain sound. Async operator leads. |
| SEV-4 | Non-user-facing telemetry or development operations degraded. Observability operator leads. |

Roles are responsibilities for the local exercise, not an invented company or
staffing promise. One person may hold multiple roles. Escalate an async symptom
to SEV-1 if evidence shows authoritative corruption or a future-timeline event
entering recovery. The [database recovery](../runbooks/database-recovery.md),
[Kafka](../runbooks/kafka.md), [Sidekiq](../runbooks/sidekiq-redis.md),
[projection reconciliation](../runbooks/projection-reconciliation.md) and
[observability](../runbooks/observability.md) runbooks give actions.

## Secured operator boundary

The internal operator API is disabled by default and requires an isolated
process with `OPERATOR_API_ENABLED=true`; ordinary public Compose API processes
do not enable it. `GET /api/v1/operator/auctions/:id` returns only PostgreSQL status/revision,
per-auction pending outbox counts, audit receipt count and Redis projection
presence/revision. `POST .../:id/reconcile` performs one current-PostgreSQL
projection check with the existing bounded repair behavior. Phase 20 session,
operator role and CSRF rules apply. It cannot set a bid, price, winner, leader,
reserve or closing state. A PostgreSQL `operator_action_audits` row records
actor, auction, action, result and time around a requested repair; security
telemetry records success/degradation. No raw key, private maximum or reserve
amount is returned. Focused authorization/privacy/repair/fence tests passed;
broader regression remains pending.

## Integrated local game day

`PHASE22_KAFKA_DRILL=1 PHASE22_LIVE_DRILL=1 scripts/recovery/phase22-pitr`
completed against dedicated PostgreSQL, Redis, old/fresh Kafka, API replicas,
operator process, Collector and Prometheus. The final successful ignored log is
`apps/api/tmp/phase22-live-drill-clean.log`; the sensitive ignored backup/WAL
directory is `apps/api/tmp/phase22-recovery.ML1Hbt`. Earlier attempts exposed
only harness errors: an invalid fixture count query, stale nginx upstream
resolution during replica recreation, a WAL archive check at a segment
boundary, and shared Collector samples contaminating the alert baseline. The
final run used the unchanged four ordinary alert rules with disposable
telemetry storage and a one-minute local metric expiration. Ordinary Collector
configuration was not changed.

| Local observed UTC time | Event and evidence |
| --- | --- |
| Before 19:02 | `pg_verifybackup` passed; T1/T2/T3 acknowledged, old Kafka and Redis reached revision 5. Queue inspection found five notification hints, two maintenance scans, zero Retry/Dead/Scheduled. Prometheus metric 0, rule inactive. |
| 19:02:14 | SEV-1 database recovery declared; owner role `database-recovery`. Public API ingress and both replicas returned controlled 503 for authenticated mutation, read returned 503, authority counts/revision unchanged; public replicas then stopped. Old broker stopped and retained for forensics. |
| About 19:04 | Real Kafka outbox age crossed 90 seconds; Prometheus rule was observed pending. |
| 19:05:30 | `OutboxBacklogOld` firing with measured age 216 seconds. No synthetic alert was posted. |
| About 19:05:36–19:05:40 | Physical PITR promoted in two seconds after start; restored revision 4 preserved policy, price, leader, deadline, bids, private maximum, two idempotency rows and four outbox rows. T2 replayed without a write. T3 bid, command and outbox revision were absent. Ahead Redis revision 5 rejected a lower seed; isolated Redis was replaced and seeded exactly at revision 4. |
| About 19:05:49–19:05:56 | Fresh Kafka endpoint received retained revisions 1–4 only. Restored audit receipts deduplicated three events and recorded one new effect. Projection replay was stale ×3/duplicate ×1; reconciliation healthy. Four Sidekiq hints and two scans were regenerated and drained; old queue/retry state was discarded. |
| 19:06:03 | Internal operator GET returned bounded revision 4, zero pending outbox, four receipts and missing projection. Anonymous/member got 401/403. Operator POST repaired one deleted public projection; PostgreSQL auction authority stayed unchanged, durable actor/target/action/result/time audit was written, and `security.privileged_action` succeeded event was emitted. |
| 19:06:51–19:06:54 | Kafka age returned to 0 and alert cleared. Public replicas were recreated without the fence against restored PostgreSQL. A fresh authenticated Charlie bid through ingress returned 201. Public ingress returned 404 for the operator route with the capability disabled on both public replicas. |

These are **local observed times**, not production RTO. The T3 client may
still remember success while the recovered server does not: PITR deliberately
excluded that command. Its absent idempotency key cannot resurrect discarded
history. The fresh post-resume bid is a new accepted command, not recovery of
T3. `RECOVERY_FENCE` remains a per-process guard; a real incident still needs
ingress isolation and all background writers stopped or drained.

## Release decision mini-drill

If the expanded schema exists and no stepped/rapid/v2 or HMAC-incompatible
state has been written, the [compatibility matrix](release-compatibility.md)
allows a reviewed old-image rollback. Once the new policy/event state exists,
the measured Phase 20 old writer accepts an underpriced stepped bid and cannot
decode v2 Kafka events. The exercise decision is to keep writers fenced and
the expanded schema, then deploy a compatible current-generation image or
forward fix. Do not blindly run `db:rollback`. This reuses the real old/new
writer and guarded-migration evidence rather than repeating that drill.

## Remaining final verification

Adversarial review, full backend/frontend/static/security gates, ordinary
Compose and browser regression, closure commit and exact-SHA hosted CI remain.
Cloud SQL PITR, managed Kafka recovery, production secret-store retrieval,
representative restore volume, production RPO/RTO, multi-region availability,
live cloud deployment, capacity and penetration testing remain unverified.
Phase 22 is not complete.
