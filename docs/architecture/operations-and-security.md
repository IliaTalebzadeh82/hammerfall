# Verification, security and operations

## Current limit

Phase 20 uses authenticated HTTP identity, owner/operator policy, a post-lock seller self-bid guard, shared Redis rate limits, early Rails and local nginx body limits, and versioned HMAC command-key digests. Auction correctness remains in PostgreSQL. Final local regression passed; production ingress proof remains outstanding; this is not a public real-money service. Local Compose credentials and named volumes are development conveniences, not backups. [Security](../security.md) and [production readiness](../production-readiness.md) state current risks.

## Security and data handling

Phase 20 implements first-party authentication and authorization, bounded command/login/Cable admission and a per-endpoint Redis failure policy. Rate limiting is not auction authority. The HMAC keyring must be distributed to all Rails replicas and kept through physical pruning; production boot rejects a missing keyring. Do not commit credentials or log tokens, raw idempotency keys, passwords, private maxima or unnecessary personal data. Metrics avoid unbounded user, auction, bid, IP or login labels. Review production origin/WSS/proxy settings, cloud edge body enforcement and connection budgets before deployment.

## Observability and failure response

Phase 22 completed an isolated PostgreSQL physical PITR exercise and
canonical [recovery](../runbooks/database-recovery.md) and
[release](../runbooks/release.md) procedures. A database restore can place
Kafka, Redis and Sidekiq on a future timeline. Keep those consumers and all
writers fenced until PostgreSQL, retained HMAC keys, outbox delivery state and
derived projections are reconciled. The
[compatibility matrix](../operations/release-compatibility.md) records
coordinated drains for policy and HMAC changes. The integrated local game day
verified future-Kafka quarantine, Redis rebuild, Sidekiq regeneration and
traffic fencing. These are local results, not a deployed DR or zero-downtime
claim.

Phase 13 implements selected OpenTelemetry spans for HTTP, auction lock wait,
decision/proxy work, outbox publication, Kafka/Sidekiq, server broadcast,
closing and reconciliation. W3C trace context crosses HTTP, jobs and Kafka
transport metadata. Bounded Prometheus metrics cover bid outcomes/latency,
lock wait, extensions, close lag, backlog/age/failures, broker lag, projection
drift/repair and server broadcast lag. Structured boundary JSON logs exclude
secrets and private commands. The provisioned Grafana dashboard addresses
auction, messaging, consistency and runtime questions. See the
[observability contract](../observability.md) and
[runbook](../runbooks/observability.md) for what each signal cannot prove.

The [Kafka runbook](../runbooks/kafka.md) covers backlog, poison, replay and
operator offset recovery. The [Redis projection runbook](../runbooks/redis-projection.md)
covers loss and manual PostgreSQL rebuild. The [reconciliation runbook](../runbooks/projection-reconciliation.md)
covers drift, safe repair, leases and operator review. The observability runbook
covers close lag and PostgreSQL lock contention signals. The [failure model](../failure-model.md)
covers current PostgreSQL/Redis/Kafka outage, worker/consumer/Rails crash,
dropped sockets, delayed publication and duplicate delivery. The
[benchmark reports](../benchmarks/) and [recovery evidence](../operations/phase-22-final.md)
record measured latency and projection recovery separately.

## Evidence and deployment gates

Use RSpec, Vitest/Testing Library, Playwright and k6 for their recorded scopes. Critical concurrency/distributed tests exercise actual PostgreSQL and relevant Redis/Kafka, multiple Rails instances and failure injection where feasible. Record benchmark environment, git commit, configuration, setup, p50/p95/p99, accepted/rejected/error counts, contention and interpretation in `docs/benchmarks/`; never invent numbers. Compare pessimistic versus optimistic/CAS approaches only with equivalent correctness and realistic load, then decide on more than speed. Profile DB locks/queries, CPU, memory, concurrency and pools before optimizing.

Phase 18 used local kind manifests for API/web/workers, probes, resources,
configuration, manual scaling, graceful shutdown and failure exercises.
PostgreSQL, Redis and Kafka remain
external Compose dependencies. See [ADR-014](../adr/014-local-kubernetes-process-orchestration.md)
and the [ExecPlan](../plans/phase-18-execplan.md). Phase 19 produced a
default-disabled Terraform/GCP reference with estimated costs and static/local
validation; it was not deployed. Normal CI needs no deploy credentials. The
Phase 24 [ExecPlan](../plans/phase-24-execplan.md) classifies final findings
and fixes reasonable Critical and High issues.

## Evidence and study route

The [benchmark reports](../benchmarks/) contain the actual local scenarios,
load results and limits. The [Phase 16 chaos report](../chaos/phase-16-final.md)
records injected failures. [Production readiness](../production-readiness.md)
collects remaining deployment limits. The [learning guide](../learning-guide.md),
[code map](../code-map.md) and [interview guide](../interview-guide.md) route a
reader through the adopted decisions, implementation and evidence. Phase 21
rejected an optional bidding-panel experiment; see its
[policy report](../marketplace/phase-21-final.md).
