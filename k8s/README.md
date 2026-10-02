# Local Kubernetes proof

Phase 18 runs only Hammerfall's application processes in one kind cluster.
PostgreSQL, Redis and Kafka stay in Compose. This is a local process lifecycle
proof, not a production deployment or resource sizing guide.

## Start

Prerequisites: Docker, Docker Compose, kind, kubectl and `rg`. Copy
`.env.example` to `.env` as for Compose. From the repository root:

```sh
bash k8s/local/up.sh
kubectl --context kind-hammerfall -n hammerfall port-forward svc/web 8080:8080
```

Open `http://127.0.0.1:8080`. The script stops Compose application containers,
starts only `db`, `redis`, `kafka` and `kafka-init`, builds uniquely tagged
API/web images, loads them into kind, prepares the local database with a
Kubernetes Job and applies manifests rendered with those image tags.
`--no-build` reuses the last tag built on this workstation for unchanged
application code and configuration; run the ordinary command after edits or
in a new checkout.
To return to the ordinary Compose application after the Kubernetes exercise,
run `kind delete cluster --name hammerfall` and then `docker compose up -d`.
This removes only the local cluster; the Compose stateful volumes remain.

The web Service targets an Nginx sidecar on port 8080. It serves Next.js pages
from `next start` in the same pod and routes `/api` and `/cable` to the API
Service. The browser uses the web origin; no Kubernetes API URL is compiled
into browser assets. The API Service selects two Rails pods. API `/ready`
queries PostgreSQL and gates traffic; `/up` checks the running Rails process.
Redis/Kafka failure does not make an otherwise usable API fail liveness.

## Dependency routing

The script joins `hammerfall-control-plane` to the Docker Compose
`hammerfall_default` network. It reads the current IP of each external
container and creates a selectorless Service plus EndpointSlice named `db`,
`redis` and `kafka` in the `hammerfall` namespace. Pods use these DNS names.
The Compose broker advertises `kafka:9092`, which resolves to the Service from
pods. Rerun the script after a Compose dependency is recreated because its IP
may change. This address discovery is local plumbing only.

The script reads the local Compose database username and pipes the exact
password bytes into a Kubernetes Secret. The Secret and generated
EndpointSlices exist only in the local cluster; no credential or generated
Secret YAML is committed.
The fixed local database name is `hammerfall_development`. Rails runs with
development settings and reloading disabled so the proof shares the Compose
demo data; it does not verify production Rails configuration. Telemetry export
is disabled unless a later local exercise explicitly configures a collector.

## Inspect

```sh
kubectl --context kind-hammerfall -n hammerfall get pods
kubectl --context kind-hammerfall -n hammerfall get endpointslices
kubectl --context kind-hammerfall -n hammerfall logs deployment/kafka-audit-consumer --tail=20
kubectl --context kind-hammerfall -n hammerfall scale deployment/api --replicas=3
kubectl --context kind-hammerfall -n hammerfall scale deployment/api --replicas=2
```

The local Cable replacement harness requires a web Service port-forward and
Chrome or Playwright Chromium. From the repository root, for example:

```sh
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome node apps/web/scripts/phase18_k8s_cable.mjs
```

It creates a test auction, deletes API pods to observe socket recovery, then
checks a new Cable hint and REST-rendered price. Run it only against the local
kind cluster.

All Deployments restart exited processes. Only API and web have HTTP traffic to
gate with readiness probes. Background process progress must be checked using
outbox, job, offset, projection and lease evidence; `Running` alone does not
prove successful work. The closer and scheduler have one operational replica,
but PostgreSQL locking and leases remain their correctness controls. Resource
requests and limits are conservative local starting values, not production
capacity findings. Manual scale is used because an HPA target and database
connection budget have not been validated. The one-node cluster cannot prove
high availability or voluntary-disruption protection.

## Scope

No PostgreSQL, Redis or Kafka pods, StatefulSets, cloud resources, production
ingress, HPA or leader election are part of this proof. Pod loss can interrupt
a response or Cable socket. Clients recover ambiguous mutations with the same
idempotency key and payload, then GET current state; Cable hints are followed
by REST. See [ADR-014](../docs/adr/014-local-kubernetes-process-orchestration.md)
and the [Phase 18 ExecPlan](../docs/plans/phase-18-execplan.md).
