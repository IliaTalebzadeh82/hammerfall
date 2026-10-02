# Current handoff — Phase 17 complete

Updated: 2026-10-02. Phase 17 is complete. Phase 18 — Kubernetes has not
started; begin it only on an explicit request. Read its
[specification](../phases/phase-18.md) and use the
[context map](../context-map.md) for targeted architecture when that work
begins. The [Phase 17 final report](../multi-instance/phase-17-final.md) is
the concise authority; its [ExecPlan](../plans/phase-17-execplan.md) indexes
the two detailed sessions and verification evidence.

Two local Rails/Puma API containers run behind nginx without sticky routing.
Proxy GETs and command responses reached both; sequential/concurrent bidding,
proxy/max bids, same-key replay and ambiguous committed/uncommitted retries
remained correct across replicas. PostgreSQL row locks, SQL uniqueness,
post-lock DB time, transactions, idempotency rows, outbox rows and public
revision remain authoritative. The API processes are replaceable executors.
Redis, Kafka, Sidekiq and Cable remain downstream delivery/derived state.

PostgreSQL Action Cable pub/sub carried public revision hints across API
processes. The browser used each hint to fetch authoritative REST state.
Stopping the socket-owning replica disconnected Cable but left the surviving
replica able to serve bids and reads. CDP showed Action Cable's monitor
created a reconnect attempt; nginx's five-second Cable upstream connect
timeout let it retry the survivor. A confirmed resubscription and REST
recovery followed in retained local runs. Visibility REST recovery still
matters for missed hints. Rejoining the stopped API immediately read current
PostgreSQL state without reconstruction. No uninterrupted delivery or
reconnect-latency promise exists.

One closer and one reconciliation scheduler are operational roles. Closure
uses auction row locking and DB-time recheck; scheduled reconciliation uses
durable PostgreSQL leases. Replica-local diagnostics do not decide outcomes.
Each additional API may add concurrent PostgreSQL work and connections: the
two API pools are configured for three each, plus Cable/background services.
One snapshot found 13 development connections including the sampler against
`max_connections=100`; this is not a capacity finding.

Final local gates: 449 backend examples, zero failures, three opt-in pending;
73 frontend tests; seven normal Chrome scenarios; rebuilt Compose and
runtime/Kafka/Redis/background smokes; static/security/config checks. Hosted
[GitHub Actions run 36999538692](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36999538692)
passed API, web and Compose, including cross-replica correctness and browser
steps, on verification SHA `d36d05d831ed8d01376903dffbb39e27620c5199`.

The proof covers two local API processes only. It does not establish linear
throughput, production capacity, Kubernetes/autoscaling, PostgreSQL failover,
large replica counts, cloud load balancing or regional failover. Phase 18 has
not started.
