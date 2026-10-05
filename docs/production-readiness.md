# Production readiness

This is a development system with tested concurrent manual/proxy bidding and deadline closure, not a
production auction service. PostgreSQL serializes each auction's writers; a hot
auction can queue requests and exhaust connection capacity. Phase 14 measured
short local Compose workloads, but established no production throughput or
capacity target. Long outer transactions retain locks longer.

Phase 20 added first-party authentication, authorization, shared
Redis rate limits, an early Rails request-body guard, local nginx limit,
versioned HMAC idempotency digests and structured security events. The
[final review](security/phase-20-final.md) records regression and hosted
closure evidence. No production backup/restore procedure,
production deployment or production-grade operating program exists; durability,
release and operating policy are assigned to [Phase 22](phases/phase-22.md).
No professional penetration test or live cloud deployment was performed.
Local runbooks cover specific failures.
Phase 21 adds persisted stepped increments, hidden reserve and regular/rapid
closing. These policies require one PostgreSQL authority and compatible
snapshot readers during rollout. The rapid window increases sensitivity to
request/lock latency without promising FIFO fairness or an exact closer SLA.
Active reserve edits, payment reservations, category/country restrictions and
livestream infrastructure remain excluded; see the [policy report](marketplace/phase-21-final.md).
Production Rails boot requires an explicit `API_ALLOWED_HOSTS` allowlist, but
host filtering and the initial identity controls do not make the API safe to expose.
The API limits `/api/v1` bodies to 32 KiB before Rails JSON parameter parsing,
and local nginx enforces the same bound. Content-Length, chunked and Next rewrite
paths were tested locally. Puma or Next may buffer bytes before this Rack guard;
the static GKE Gateway reference has no separately verified edge body limit.
Choose and prove a supported cloud enforcement point before public ingress.
Production replicas must share one `SECRET_KEY_BASE` and byte-identical validated
HMAC keyring content for each key ID. Initial rollout must drain old executor code
before any HMAC-version write because old code lacks the advisory lock; mixed
old/new writers are not supported. Previous HMAC keys remain configured until
every row using them is
physically pruned. Redis-outage fallback quotas are per process and can be
multiplied by replica switching. An already established Cable socket may keep
receiving public invalidation hints after session revocation until disconnect.
Reads spanning multiple queries are not snapshot-consistent.
Local Compose credentials are disposable; services bind to loopback. Named volumes
provide local persistence, not backups. The sequence migration requires stopping
old writers for a maintenance rollout, not an untested rolling deployment.

Before real-money use, implement and test remaining invariants/failure scenarios,
review security, verify durable backup restores, measure capacity and assign
operational ownership. See progress.md and ADR-003 for actual evidence and limits.


Proxy commands perform extra private-state queries and up to two visible INSERTs
while holding the same row lock. No capacity target is established. Maximum privacy
is representation filtering, not identity authorization or encryption at rest.
Downgrading the Phase 3 schema refuses to destroy existing private instructions;
an explicit preservation plan is required for a populated database.

Phase 4 uses one PostgreSQL wall-clock authority after the row lock, atomic soft
close and an independent Rails closer role. Polling is not a freshness SLA. Multiple
closers safely overlap but may duplicate work or queue behind the same hot auction.
Database wall-clock adjustments and outages remain operational dependencies. There
is no fallback to application clocks. New timing history needs preservation before
downgrade. ADR-005 records the exact decision-time and delayed-status limits.

Phase 5 stores scoped client-key digests, semantic fingerprints and public terminal
responses in the same PostgreSQL transaction as bidding. Key ownership precedes
Auction locking; replay bypasses domain state/time evaluation. Internal Auction
calls remain unwrapped. Records default to seven-day prune eligibility; expired rows
reserve their keys until physical deletion. This is bounded retry protection, not
permanent deduplication or authentication. Retained outcomes add storage and lock
lifetime; cleanup and API snapshot compatibility need operational ownership. No
performance improvement is claimed without measurement. See ADR-006.

Phase 6 now provides a working browser auction UI with session-based retry recovery
and real-API browser evidence. Phase 20 adds authentication and authorization, but
the service is not ready for real-money use. Reads become stale between explicit,
visibility, command and expiry refreshes; Phase 7 also adds best-effort Cable
invalidations. Browser storage can be lost and clocks can move. The one-hour client
retry horizon is conservative, not a durability SLA.
Separate auction/history GETs are not one consistent snapshot. No exhaustive
accessibility audit, cross-browser certification or performance benchmark is claimed.

## Phase 7 review gates

Implemented public invalidations do not imply production readiness. Review exact
origin/WSS/proxy configuration, authentication and authorization, connection limits,
PostgreSQL listener connections, shared HTTP/Cable pool contention, hot-auction
fanout and REST amplification. LISTEN/NOTIFY is ephemeral; the Phase 9 outbox
preserves intent until queue enqueue, but does not guarantee Cable delivery or
measured capacity.

## Phase 8 queue boundary

Sidekiq and Redis now deliver public invalidations asynchronously and schedule a
read-only PostgreSQL sweep. The Phase 8 commit-to-enqueue crash gap was closed by
Phase 9's transactional outbox; Redis/worker outage or loss after acknowledgment
can still leave clients stale. AOF and a local named volume are not a
backup or delivery guarantee. Job retries are bounded and need Dead-set ownership.
The sweep reports possible PostgreSQL drift without repair. There is still no
authenticated identity or projection repair,
capacity benchmark or production operations stack. Review Sidekiq/DB connection
budgets, Redis persistence/HA and job/runbook ownership before public deployment.

## Phase 9 outbox boundary

The outbox makes public revision and publication intent atomic in PostgreSQL.
The independent publisher retries pending rows after API death or Redis outage;
multiple publishers claim with `SKIP LOCKED`. A successful queue enqueue marks
the row published, so subsequent Redis loss, exhausted job retries or Cable loss
can still lose a hint. Operators need backlog/oldest-age/retry monitoring and
poison-row response. Current aggregate publisher logs are not a production alert
system. Redis network operations time out, but no full-cycle latency or capacity
benchmark exists. Each publisher process holds one PostgreSQL connection and row
lock through network delivery. Kafka and Sidekiq can skip the same locked event
and retry next cycle while they advance other rows; backlog can extend connection
occupancy. Measure publisher count, pool headroom and delivery latency before
scaling processes. REST recovery remains required for browser freshness. See
[ADR-010](adr/010-transactional-public-outbox.md) and the [runbook](runbooks/sidekiq-redis.md).

## Phase 10 Kafka boundary

The public outbox also carries a versioned public domain snapshot. A separate
Kafka publisher waits for broker delivery before acknowledging the row; an
audit consumer writes receipt and side effect before committing its offset.
This provides recoverable local propagation, not exactly-once delivery or a
production event platform. The Compose broker is single-node, plaintext,
replication factor one. There is no broker backup, high availability, TLS/ACL,
schema registry, retention/capacity study, lag alerting or production poison
workflow automation. Audit is not a Redis read model. Kafka outage cannot
change auction correctness, but can delay derived consumers indefinitely.
Review [ADR-011](adr/011-kafka-domain-events.md) and the [runbook](runbooks/kafka.md)
before extending consumer groups.

## Phase 11 projection boundary

Redis now holds a derived public snapshot for an explicit eventual endpoint.
Atomic revisions handle duplicate and reordered Kafka records; they do not
guarantee synchronous freshness. Ordinary GET and commands remain PostgreSQL
backed. The Redis keyspace is disposable, with manual PostgreSQL seeding after
loss. A valid stale key can remain until Phase 12's scheduled scan detects
and repairs it; manual rebuild remains available. Equal-conflicting,
corrupt and ahead keys still require operator review. The local outage,
replay and rebuild checks do not establish production replay time, capacity,
Redis/Kafka HA or backup policy. The lease bounds scheduled overlap but no
maximum detection or repair delay is guaranteed. See [ADR-012](adr/012-redis-public-projection.md)
and [ADR-013](adr/013-bounded-reconciliation-scan-ownership.md).

## Phase 13 observability boundary

The optional local Collector, Prometheus, Tempo and Grafana stack receives
bounded traces and metrics; Rails also emits correlated structured boundary
logs. Live HTTP, Sidekiq and Kafka traces and telemetry-peer outages are
documented in the [observability contract](observability.md) and
[runbook](runbooks/observability.md). Export may time out or drop data without
changing an auction outcome. A trace, dashboard panel or empty failure counter
does not prove business correctness or absence of failures.

This is still an incomplete local demo. Phase 20 owns public ingress and
remaining identity/security hardening; Phase 22 owns backup/restore, disaster recovery, SLOs and
alerts. High availability and production capacity remain unverified. Phase 18
verified local kind orchestration, not production Kubernetes deployment.
The Ruby OpenTelemetry metrics SDK is alpha. Local outage exercises do not
establish performance or queue saturation behavior.

## Phase 14 local load boundary

[Retained benchmark reports](benchmarks/README.md) cover normal, one-row hot,
closing, duplicate, final-ten-second and Action Cable fanout workloads. The
largest clean local final-ten burst was 600 contenders. A 1,000-contender
attempt hit the API process's 1,024-open-file soft limit, producing 28 server
errors and 64 timeouts; PostgreSQL reconciliation still found a valid final
state. At 64 hot-auction VUs, HTTP p95 rose to 935 ms while auction-lock p95
remained in a ≤25 ms histogram bucket. Puma admission and database checkout
wait were not instrumented. These shared-host results cannot determine
production capacity, a safe file limit, or the best pool/concurrency setting.
At 500 k6 Cable subscribers, all subscriptions were confirmed; receipt of
invalidation hints does not establish durable or universal browser delivery.

## Phase 15 performance boundary

The [final causal review](benchmarks/phase-15-final.md) and its Session 1/2
reports add Puma admission, DB checkout/queue, CPU, SQL, FD and memory
evidence. Local hot load showed substantial Puma backlog while baseline DB
checkout and auction-lock wait were small. Development request file checking
consumed CPU; disabling it improved local accepted work but did not reliably
improve the HTTP tail. Five Puma threads moved pressure into the DB pool, and
pool five removed those waits without repeatable end-to-end gain. Neither
tuning change was adopted. OTel remains enabled in the measured local stack.

There is no measured production worker/thread/pool setting, exact per-request
pre-Rack delay, safe FD limit, maximum WebSocket fanout, long-term memory-leak
finding, production capacity, SLO or cloud-sizing conclusion. The ordinary
local development runtime remains three threads/pool three with reloading on;
diagnostic profiling is opt-in. A production traffic and resource study is
needed before deployment sizing.

## Phase 16 local failure boundary

The [final chaos review](chaos/phase-16-final.md) links direct PostgreSQL
checks, retained Redis/Kafka/worker/API faults and browser REST recovery.
Kafka publication is at least once: a publisher died after broker acceptance
and retried the same event. Consumer event-ID deduplication kept one durable
audit effect, and revision guards prevented Redis regression. A lost HTTP
response after commit requires a same-key/same-payload client retry; the
historical outcome is then replayed, followed by a fresh GET for current
state. A pre-commit API death rolled its command and outbox back together.

These one-instance Compose observations do not establish multi-instance
behavior, PostgreSQL failover, Kafka/Redis high availability, production
recovery time or durable WebSocket delivery. A browser can remain stale during
a silent missed hint until an explicit/visibility/reconnect/later-hint REST
refresh. Restore failed dependencies, inspect pending outbox/consumer lag and
reconcile stale projections using the existing runbooks; corrupt or ahead
projection keys still require operator review.

## Phase 17 local multi-instance boundary

Two Rails/Puma containers behind local nginx preserved PostgreSQL command
correctness across replica changes, same-key retries, concurrent bids and
deadline/close races. Action Cable used PostgreSQL pub/sub across processes;
its public hint still requires REST recovery. A socket-owning replica's death
interrupts the connection. The client monitor retries, and nginx's bounded
Cable upstream connect timeout lets a retry reach the surviving replica; no
reconnect time or uninterrupted delivery is guaranteed. A missed hint can
leave an open page stale until a REST recovery trigger.

Each added API may increase concurrent work reaching the same PostgreSQL rows
and consume more DB connections. The two local API pools are configured for
three each; Cable and background roles add connections. A single snapshot of
13 development connections against 100 configured is not a capacity claim.
This phase does not establish production high availability, PostgreSQL
failover, large-replica behavior, cloud load balancing, autoscaling or
Kubernetes operation. Background closer and scheduler process counts are
operational choices; their correctness protocols are PostgreSQL locks and
leases. See the [final review](multi-instance/phase-17-final.md).

## Phase 18 local Kubernetes boundary

The [Phase 18 final review](kubernetes/phase-18-final.md) verifies a fresh
one-node kind cluster running two API and two web pods plus all seven
background roles. It covers probes, bounded API/web rollouts, manual scaling,
active API termination and idempotent retry, Cable reconnection, worker
replacement, Kafka consumer rebalancing and a fresh-cluster lifecycle. A
transient 502 occurred in one of 40 reads during fresh API pod deletion;
subsequent reads and replacement state converged. Compose development startup
still works. PostgreSQL, Redis and Kafka remain external Compose containers.

This is an application orchestration proof. It does not verify production
Kubernetes configuration, cloud networking, managed or highly available
stateful dependencies, node failure, production TLS/secrets, autoscaling,
capacity or long in-flight worker termination. Resource settings are local
starting values. PostgreSQL transactions, idempotency and durable outbox
protocols remain the correctness mechanisms during process loss.

## Phase 19 cloud reference boundary

The [Phase 19 final review](cloud/phase-19-final.md) adds a near-deployable,
default-disabled Terraform/GCP reference and GKE overlay. Local Compose and
kind regression, official-provider schema/mock validation, workload identity
and mount checks, and static Gateway routing checks passed. No GCP project was
authenticated, no resource was created and no managed-service connection was
tested. PostgreSQL remains the only auction authority.

This is not a proven production GCP deployment. Classic Redis has private TLS
but no application AUTH and remains disabled; a separate security decision is
required before enabling it. GKE admission/WIF/CSI, Cloud SQL verified TLS and
failover, Redis TLS/failover, managed Kafka OAuth/ACLs, real Gateway HTTPS/WSS,
multi-zone availability, DR/restore, production sizing, HPA capacity and an
actual monthly bill remain unverified. The manifest-based ~70-connection
planning budget is not measured Cloud SQL usage. A credentialed provider plan,
secure bootstrap, real network/TLS tests and operational exercises are required
before claiming deployment readiness.

## Phase 22 Session 1 recovery and release boundary

A disposable PostgreSQL 18.6 cluster now demonstrates physical base backup,
`pg_verifybackup`, archived-WAL replay to a selected LSN, and a domain-correct
PITR that retains T1/T2 but excludes T3. The restored command replayed and an
ahead Redis projection had to be deleted and rebuilt from PostgreSQL. A real
Phase 20 application worktree wrote fixed data on the expanded schema, but
accepted an invalid bid on a stepped auction; current code rejected it. The
closing-policy rollback guard refused rapid data. See the
[Session 1 report](operations/phase-22-session-1.md),
[recovery runbook](runbooks/database-recovery.md) and
[release policy](operations/release-compatibility.md).

This is a local fixture, not production DR. Cloud SQL restore, Kafka reset and
republish, secret-store retrieval, full service freeze/resume, representative
data volume, production RPO/RTO, deployment promotion and alerts remain
unverified. Current Kafka projection consumers do not consult PostgreSQL for
each event; a pre-PITR broker can be ahead of restored authority and must be
quarantined or handled under a reviewed recovery plan. Phase 22 remains open.
