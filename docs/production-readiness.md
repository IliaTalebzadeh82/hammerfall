# Production readiness

This is a development system with tested concurrent manual/proxy bidding and deadline closure, not a
production auction service. PostgreSQL serializes each auction's writers; a hot
auction can queue requests and exhaust connection capacity. Phase 14 measured
short local Compose workloads, but established no production throughput or
capacity target. Long outer transactions retain locks longer.

There is no authentication, authorization,
rate limiting, production backup/restore procedure, production deployment or
production-grade operating program. Local runbooks cover specific failures.
Production Rails boot requires an explicit `API_ALLOWED_HOSTS` allowlist, but
host filtering does not make the unauthenticated demo API safe to expose.
The API has no pre-parse request-body byte cap; its JSON parser can consume
resources before controller validation. A future public ingress must enforce a
streaming body-size limit and test chunked requests before accepting untrusted
traffic. Phase 12.5 leaves this at the deployment/security boundary because
there is no production ingress or authenticated public deployment yet. The
repository's Puma and Next rewrite configuration set no explicit request-body
limit; no effective framework or proxy limit has been verified.
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
and real-API browser evidence. It still has no authentication, authorization or
real-money readiness. Reads become stale between explicit/visibility/command/expiry
refreshes; Phase 7 also adds best-effort Cable invalidations. Browser storage can
be lost and clocks
can move. The one-hour client retry horizon is conservative, not a durability SLA.
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

This is still an unauthenticated local demo. Public ingress hardening, backups
and restores, high availability, production capacity measurements, SLOs, alerts,
disaster recovery and Kubernetes deployment remain unverified or future work.
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
