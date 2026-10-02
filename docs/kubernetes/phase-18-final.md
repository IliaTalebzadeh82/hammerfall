# Phase 18 — local Kubernetes final review

Date: 2026-10-02. Scope: application process orchestration in a one-node kind
cluster. [Session 1](session-1.md) and [Session 2](session-2.md) retain the
longer lifecycle observations; [ADR-014](../adr/014-local-kubernetes-process-orchestration.md)
records the boundary. This review does not claim production Kubernetes
readiness.

## Boundary and process roles

Kubernetes schedules and replaces two Rails API pods, two Next.js web pods
(each with an Nginx runtime proxy), and one pod each for Sidekiq, the Sidekiq
outbox publisher, the Kafka outbox publisher, the Kafka audit consumer, the
Kafka projection consumer, the auction closer, and the reconciliation
scheduler. A one-shot `db-prepare` Job runs before the Deployments. PostgreSQL,
Redis and Kafka stay in Compose. The kind node joins the Compose network;
selectorless Services and generated EndpointSlices route to their current
container addresses. Kafka's advertised `kafka:9092` name resolves to the
matching Kubernetes Service. The local database Secret is generated from
Compose environment bytes at setup time, never committed. A ConfigMap injects
non-secret settings. API and web images contain source and a production Next.js
build under unique local tags; they do not contain the database password.

Kubernetes decides process placement, Service membership and restarts. It does
not decide bid legality/order, private maximum priority, command identity,
deadline, public revision, outbox identity or winner. Rails enforces business
rules against PostgreSQL transactions, locks and database time. Redis, Kafka,
Sidekiq and Cable are derived delivery paths. Pod identity is only a diagnostic
label and does not enter auction state.

## Probes, resources and rollouts

API `/ready` queries PostgreSQL: an API unable to reach authority is withheld
from Service traffic. API `/up` checks Rails process liveness without Redis or
Kafka, avoiding a restart storm during an optional downstream outage. The web
container checks its local Next.js redirect (`/`); the proxy readiness checks
that route through local Next.js, while proxy liveness uses its own
`/proxy-health`. Worker Deployments have no HTTP traffic to gate and restart on
process exit; `Running` does not prove jobs, offsets, outboxes or leases are
advancing. Those require durable progress checks.

| Role | CPU request/limit | Memory request/limit | Grace |
| --- | --- | --- | --- |
| API | 250m / 1 | 384Mi / 1Gi | 45s |
| web Node | 100m / 500m | 128Mi / 512Mi | 30s pod |
| web Nginx | 25m / 250m | 32Mi / 128Mi | 30s pod |
| Sidekiq | 100m / 500m | 256Mi / 768Mi | 30s |
| other background roles | 50m / 500m | 128Mi / 512Mi | 30s |

These are local guardrails, not capacity measurements or production sizing.
Session 2's cgroup snapshot showed no OOM events and nonzero CPU throttling
counters, without a utilization series. Metrics-server is absent, so
`kubectl top` is unavailable. Manual 2→3→2 API scaling and Kafka consumer
1→2→1 rebalancing were tested. HPA is absent because there is no validated
metrics target or shared PostgreSQL connection budget; more replicas can add
hot-row contention. PDB is absent because this one-node cluster cannot prove
multi-node voluntary-disruption availability. One-replica Deployments can
overlap during rolling updates. Closer locking and DB-time recheck, scheduler
PostgreSQL leases, publisher row claims and retry identities, and consumer
duplicate guards make overlap safe; replica count is not the correctness lock.

## Lifecycle and failure observations

- Session 1 proved two Ready API replicas, Service routing, 80/80 GETs through
  deletion, current-state reads on replacement, and traffic reaching all three
  pods after manual scale. Session 2's bounded API and web rolling restarts
  each passed 100/100 reads, and API scale-down passed 100/100. A local
  `kubectl port-forward` to a selected web pod can itself disconnect on a web
  rollout; that tunnel is not the Kubernetes Service.
- Session 2 held a PostgreSQL auction lock for 35 seconds, terminated the API
  pod handling a keyed bid, and observed the original 201 complete within the
  45-second grace. A same-key retry replayed that outcome. A separate
  post-commit process crash lost the client response while PostgreSQL retained
  one completed bid and idempotency record; the same key/payload replayed the
  stored 201. Requests beyond the grace can be force-killed, so the durable
  transaction and idempotency protocol remains the safety net.
- Deleting a Cable-owning API pod closed the browser socket. Chrome observed a
  new 101 handshake and subscription, a later public revision hint and an
  authoritative REST refresh. Cable is invalidation-only; there is no
  reconnect latency or universal hint-delivery guarantee.
- Replacing Sidekiq, both publishers and both Kafka consumers during 20 bids
  preserved all authoritative bids; outboxes, audit and Redis projection
  caught up. Both Kafka consumer groups redistributed three partitions at
  1→2→1 replicas, processed subsequent events and had sampled zero lag, with
  no duplicate durable audit effect. Broker HA was not tested. Exact long
  in-flight worker termination was not proven.
- After closer replacement, a due auction without a bid closed without a
  winner and a soft-close auction closed later with the correct winner.
  Scheduler replacement resumed both scan types, and Sidekiq completed them.
  Forced termination while a scheduler lease is held remains untested live;
  the PostgreSQL lease protocol is covered separately.

## Fresh-cluster and regression evidence

The previous cluster was deleted and `kind get clusters` reported none. The
documented `bash k8s/local/up.sh` then created a kind v0.33 cluster on pinned
Kubernetes server v1.36.4 with local kubectl v1.35.9, eliminating the former
two-minor skew. The pin uses the [kind v0.33 published node digest](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0).
The script built and loaded `hammerfall-api:phase18-20261002142102-834484`
and `hammerfall-web:phase18-20261002142102-834484`, generated the Secret and
all three EndpointSlices, completed `db-prepare`, and brought all nine
Deployments to Ready: 2 API, 2 web and seven background pods. All 13
application containers had zero restarts; no CrashLoopBackOff or OOMKilled was
observed. Dependency EndpointSlice addresses equaled the current Compose
container IPs. A SHA-256 byte comparison of the Compose password and Secret
passed without printing the value, including the prior newline boundary.
Pod DNS resolved all three external Services. API `/ready` and `/up`, web and
proxy health responded; worker logs showed new event processing.

Fresh auction 660 ran create, schedule, activate, two accepted bids, low-bid
rejection, close, repeat close and post-close rejection through the web proxy.
Direct PostgreSQL state was `closed`, price 11000, leader/winner 4123,
revision 6 and two bids. On a subsequent API pod deletion, 39/40 bounded
reads returned 200; one returned 502. Nginx logged an upstream connection
refusal during the termination transition. Reads immediately resumed, both
replicas returned Ready, and a replacement pod read auction 660 at revision 6
directly. This is a real transient read failure, not uninterrupted availability.
Safe GETs can be retried; ambiguous mutations require the original
idempotency key and payload.

Fresh Chrome Cable harness auction 661 observed original 101/subscription,
socket closure after owner deletion, a new 101/subscription, revision 3 hint
and rendered REST-backed price. The normal Playwright suite against the kind
web proxy passed 7 scenarios, with the Compose-only worker-fault scenario
skipped. No browser result was inferred from a notification alone.

`scripts/check` passed 450 backend examples, 0 failures, 3 intentionally gated
pending live Kafka cases (seed 31585); RuboCop inspected 132 files with no
offenses; Brakeman 8.1.0 reported zero warnings/errors; Zeitwerk passed;
frontend lint, format, typecheck, 74 Vitest tests and production build passed.
`bundler-audit` found no vulnerabilities. Ruby syntax passed for 129 files;
Python AST parsing, Node syntax, shell syntax, nginx `-t`, Compose config and
`git diff --check` passed. Base manifest client and server dry-runs passed;
the Job server dry-run passed under a temporary validation name because an
existing completed Job's pod template is immutable. The fresh setup actually
applied the intended Job and all base resources. The image configurations
showed no database password or other application Secret value. Separate
`docker build --no-cache` runs for both Dockerfiles passed, including a fresh
`npm ci` and Next.js production build. An initial uncached API attempt hit a
transient Docker Hub 403 while resolving the Ruby base image; a direct base
pull and retry passed. Container filesystem checks found the intended source
and `.next` output, with no `.env` or Rails master key in either image.

After the Kubernetes evidence was collected, the kind cluster was removed and
`docker compose up --build --wait --wait-timeout 360` restored the ordinary
development stack. Every running service with a health check reported healthy;
API `/up` and `/ready` returned 200, the web root redirected normally, and a
Compose web-proxied read of auction 660 returned 200. Hosted CI remains the
separate final regression gate for the committed closure state.

A further Phase 18 load run was omitted: Phase 17 supplied multi-instance
load/correctness evidence, while Sessions 1/2 and this fresh run exercised
Kubernetes lifecycle. A moderate replay here would not establish production
capacity or improve the remaining high-risk proof. No resource tuning was
made from the single cgroup snapshot.

## Limits and interpretation

The cluster is one-node kind with local Compose PostgreSQL, Redis and Kafka,
Rails development configuration, no stateful HA, no node failure, no
multi-node placement, no cloud load balancer or ingress controller, no
production TLS or secrets manager, no metrics-server, HPA or PDB, and no
production capacity result. Long active Sidekiq/publisher termination, cloud
rollouts, regional recovery and managed dependency networking are unproven.
Pod replacement can delay traffic, interrupt a response or socket, trigger a
consumer rebalance, and temporarily lag publication. Kubernetes process
orchestration was exercised; PostgreSQL authority and durable application
protocols continue to carry correctness.
