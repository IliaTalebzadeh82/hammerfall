# Current handoff — Phase 18 Session 2 checkpoint

Updated: 2026-10-02. Phase 18 — Kubernetes is active and explicitly
authorized. Session 2 completed the local lifecycle/failure campaign; begin a
fresh Codex conversation for the final Phase 18 completion work. Do not start
Phase 19. Read the [Phase 18 ExecPlan](../plans/phase-18-execplan.md),
[specification](../phases/phase-18.md) and
[Session 2 report](../kubernetes/session-2.md). Session 1's
[startup report](../kubernetes/session-1.md) and
[ADR-014](../adr/014-local-kubernetes-process-orchestration.md) hold the
local deployment boundary. Use the [context map](../context-map.md) for
targeted source.

The one-node kind cluster still runs two Ready API pods, two Ready web pods and
one Ready pod for each of seven background roles in namespace `hammerfall`.
PostgreSQL, Redis and Kafka remain in Compose, outside Kubernetes. Rails uses
frozen development configuration. The local web Service port-forward is an
ephemeral terminal session; restart it if needed. No production Rails, cloud,
high-availability or capacity claim has been made.

Session 2 verified an in-flight bid completing during API SIGTERM, a committed
bid whose response was lost and replayed with the same key, API/web rolling
restart and API scale-down without failures in bounded 100-request probes.
Sidekiq, both publishers and Kafka consumers were replaced during 20 bids;
all bids committed and outbox, audit and Redis state caught up. Kafka consumer
groups rebalanced 1→2→1 across three partitions and processed new events.
Closer replacement closed two due auctions correctly; scheduler replacement
enqueued both scan types and Sidekiq completed them. A real Chrome Cable
socket closed on API owner deletion, reconnected, received a new revision hint
and refreshed the page from REST. The reusable browser harness is
[here](../../apps/web/scripts/phase18_k8s_cable.mjs). Cgroup snapshots had no
OOM events; metrics-server is absent.

The next session owns final adversarial review and repairs, optional bounded
load if feasible, broad regression/lint/security/build gates, fresh-cluster
setup, relevant final browser/runtime checks, documentation/progress and hosted
CI. The active ExecPlan and Session 2 report give exact evidence and limits.
No serious correctness failure is currently known. Long in-flight worker
termination, production sizing and high availability remain unproven.
