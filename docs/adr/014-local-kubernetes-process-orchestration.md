# ADR-014: Local Kubernetes orchestrates application processes

Status: Accepted for Phase 18 local proof, 2026-10-02

## Context

Phase 17 proved that two Rails/Puma instances can execute commands against one
PostgreSQL authority without affinity. Kubernetes can replace and scale those
executors, but pod identity, scheduling and Service routing must not decide
auction state. Compose already provides a local PostgreSQL, Redis and Kafka;
kind is installed. The existing Compose images mount source and run a Next.js
development server, so they are unsuitable as immutable Kubernetes artifacts.

## Decision

Use one local kind cluster and namespace `hammerfall`. Put the API, web,
Sidekiq, both outbox publishers, both Kafka consumers, closer and reconciliation
scheduler in Deployments. API and web start with two replicas. Background roles
start with one. A one-pod closer and scheduler are operational choices only:
auction row locking/DB time and PostgreSQL reconciliation leases still make
overlap safe. No StatefulSet, CronJob, leader election, HPA or ingress controller
is introduced. Manual API scaling demonstrates the phase's scaling contract.

PostgreSQL, Redis and Kafka stay in Compose. The kind node joins the Compose
network. A setup script discovers each dependency container's current address
and creates a selectorless Service/EndpointSlice. The Kafka broker's advertised
`kafka:9092` resolves to that Service inside the namespace. The generated
database Secret is local only and is never committed. A ConfigMap holds
non-secret local values. This networking is local plumbing, not a cloud design.

Build code into API and web images. Rails runs with local development settings
and reloading disabled against the existing demo database, avoiding a claim
that production Rails configuration is verified. The web image runs `next
build`/`next start`. An Nginx sidecar routes `/api` and `/cable` to the API
Service at runtime, so the browser uses the web origin and the image contains
no cluster API address. The API liveness endpoint remains `/up`; `/ready`
queries PostgreSQL and intentionally ignores Redis/Kafka. Workers have no
Service traffic to gate; Deployments restart exited processes, and delivery
progress is verified through durable state rather than a synthetic HTTP probe.

## Alternatives considered

- Put PostgreSQL, Redis and Kafka in the cluster: outside Phase 18's boundary
  and would obscure the application process proof.
- Keep bind mounts or the Next.js dev server: would not verify replaceable
  immutable pods or a production frontend build.
- Bake a local API URL into Next.js rewrites and public WebSocket configuration:
  would freeze a local endpoint into the image. Runtime sidecar routing avoids
  it without moving auction logic to Node.
- Add HPA now: no validated metrics target or PostgreSQL connection budget.
  A CPU trigger could increase hot-row contention. Manual scaling is the
  meaningful current proof.
- Add a PDB in the single-node local cluster: it would state an availability
  goal without proving disruption resilience; revisit with a multi-node
  availability design.

## Consequences and risks

Kubernetes may create, remove and overlap processes; PostgreSQL remains the
only auction authority. A lost response still needs a same-key client retry.
Publisher delivery may duplicate after an ambiguous acknowledgment, and
consumers must remain duplicate safe. Readiness prevents routing to an API
that cannot query PostgreSQL; liveness does not cause a Redis/Kafka outage to
restart healthy Rails processes. Worker readiness here only indicates a
running container; durable progress checks are still necessary.

EndpointSlices must be regenerated when Compose containers change address.
The local cluster has one node and one external instance of each stateful
dependency. Resources are local starting values, not production capacity.
The proxy sidecar adds one process per web pod and its own health/termination
surface. API replica count multiplies potential database connections.

## Revisit when

Review this decision before production deployment, cloud networking, managed
dependencies, autoscaling, strict availability goals, or a demonstrated need
for different workload placement. Those concerns belong to a later phase.
