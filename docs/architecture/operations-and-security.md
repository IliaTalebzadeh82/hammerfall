# Verification, security and operations

## Current limit

Phase 20 Sessions 1–2 use authenticated HTTP identity, owner/operator policy, a post-lock seller self-bid guard, shared Redis rate limits, early Rails and local nginx body limits, and versioned HMAC command-key digests. Auction correctness remains in PostgreSQL. Final Phase 20 regression and production ingress proof are still outstanding; this is not a public real-money service. Local Compose credentials and named volumes are development conveniences, not backups. [Security](../security.md) and [production readiness](../production-readiness.md) state current risks.

## Security and data handling

Phase 20 Sessions 1–2 implement first-party authentication and authorization, bounded command/login/Cable admission and a per-endpoint Redis failure policy. Rate limiting is not auction authority. The HMAC keyring must be distributed to all Rails replicas and kept through physical pruning; production boot rejects a missing keyring. Do not commit credentials or log tokens, raw idempotency keys, passwords, private maxima or unnecessary personal data. Metrics avoid unbounded user, auction, bid, IP or login labels. Review production origin/WSS/proxy settings, cloud edge body enforcement and connection budgets before deployment.

## Observability and failure response

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
dropped sockets, delayed publication and duplicate delivery; later phases
extend measured latency and projection recovery.

## Evidence and deployment gates

Use RSpec, Vitest/Testing Library, Playwright and later k6. Critical concurrency/distributed tests should exercise actual PostgreSQL and relevant Redis/Kafka, multiple Rails instances, failure injection and invariant/property sequences where feasible. Record benchmark environment, git commit, configuration, setup, p50/p95/p99, accepted/rejected/error counts, contention and interpretation in `docs/benchmarks/`; never invent numbers. Compare pessimistic versus optimistic/CAS approaches only with equivalent correctness and realistic load, then decide on more than speed. Profile DB locks/queries, CPU, memory, concurrency and pools before optimizing.

Phase 18 now uses local kind manifests for API/web/workers, probes, resources,
configuration and justified manual scaling; active graceful-shutdown and
failure evidence remains in progress. PostgreSQL, Redis and Kafka remain
external Compose dependencies. See [ADR-014](../adr/014-local-kubernetes-process-orchestration.md)
and the [ExecPlan](../plans/phase-18-execplan.md). Terraform/GCP architecture
may later include GKE, Cloud SQL, Redis, a justified Kafka option, networking,
identities, secrets and observability, with estimated costs. Do not create
paid resources without explicit authorization. Normal CI must not need deploy
credentials. The final review should categorize critical/high/medium/low/future
findings and fix reasonably fixable critical/high issues.

## Specific verification and learning deliverables

- k6 should cover normal traffic, one hot auction, a final-minute/closing storm, duplicate retries and WebSocket fanout. The original challenge scenario is 1,000 simultaneous bidders on one auction in the last 10 seconds. Measure accepted bids, stale rejections, errors, throughput, p50/p95/p99 and lock contention; search for invariant violations. Store genuine results under `docs/benchmarks/` with machine, commit, configuration, setup and interpretation.
- The planned scenario files are `normal-auction.js`, `hot-auction.js`, `final-minute.js`, `duplicate-retries.js` and `websocket-fanout.js`. Build only when Phase 14 begins; keep actual benchmark results distinct from test fixtures.
- Where feasible compare pessimistic locking with optimistic locking or compare-and-swap at low and high contention. Record retries, tail latency, complexity and correctness reasoning in `docs/experiments/concurrency-strategy.md`; a single faster run is not sufficient to change production strategy.
- Failure injection should cover Kafka pause, Redis loss, consumer/Sidekiq crash and Rails crash immediately after DB commit. The expected contracts are continuing authoritative bidding with Kafka backlog, Redis-independent auction correctness, duplicate-safe restart/reprocessing and a persisted outbox that later publishes after a post-commit crash. Record observed results, not just expected ones.
- Candidate chaos scripts are `scripts/chaos/kill-sidekiq.sh`, `pause-kafka.sh`, `kill-redis.sh` and `restart-api.sh`. Document each run's actual environment, injected fault, observed result and recovery verification.
- Property/invariant tests should exercise arbitrary valid bid sequences, retry sequences and event replay, checking winner rules, logical bid counts and projection convergence. Before Kubernetes, distribute bids across multiple local Rails processes and show that no authoritative synchronization depends on local memory or one scheduler.
- [Production readiness](../production-readiness.md) must eventually cover bottlenecks, capacity assumptions, failure/security concerns, durability/backup assumptions, scaling limits, operational runbooks, unresolved risks and work required before real-money use. README should expose guarantees, architecture, hard problems, local setup, failure scenarios, benchmarks, observability and ADRs without exaggerated claims.
- [Learning guide](../learning-guide.md) should explain, for each major subsystem, the problem, tempting naive approach and failure, chosen design, provided and missing guarantees, files/tests to read and an interview explanation. Cover bid serialization, proxy bidding, idempotency, closing/soft-close, outbox, Kafka/consumer idempotency, Redis projection, reconciliation, WebSockets, observability, load tests and Kubernetes as they are implemented. [Code map](../code-map.md) should trace important HTTP, application, transaction, domain, persistence, outbox, publication and test paths. [Engineering journal](../engineering-journal.md) records substantive discoveries, not trivial activity.
- Phase 23's `docs/interview-guide.md` should answer from actual code why PostgreSQL rather than Kafka is authority, the lock choice, duplicate prevention, Kafka/Redis outage behavior, proxy ties, multi-instance closure, consumer crash before offset commit, reconciliation, eventual consistency, at-least-once delivery, bottlenecks and 100× traffic changes. Phase 24's `docs/final-review.md` should document the adversarial review and finding severities.
- The original prompt also requests a lightweight later product experiment: stable user/experiment bucketing (for example a hash modulo 100), a compact bidding-panel variant, and exposed/start/submitted/accepted/won events. Do not overbuild it; Phase 21 owns an explicit go/no-go and privacy/retention decision, as noted in [migration review](../context-migration-review.md).
- Suggested event names for that experiment are `experiment_exposed`, `bid_started`, `bid_submitted`, `bid_accepted` and `auction_won`; these are future product analytics, not existing domain events or Phase 13 telemetry.
