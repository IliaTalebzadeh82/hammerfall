# Phase 18 Session 1 — local Kubernetes startup and replacement

Date: 2026-10-02. Starting commit:
`54e5ef3ec2a2a8e01f32e8a02b22c6ebec6aa734`. This is an in-progress
local proof; Phase 18 is not complete. [ExecPlan](../plans/phase-18-execplan.md)
tracks the remaining campaigns. [ADR-014](../adr/014-local-kubernetes-process-orchestration.md)
records the deployment decision.

## Topology

- kind v0.33.0, one `kindest/node:v1.37.0` control-plane, containerd 2.3.4,
  Docker 29.8.1, namespace `hammerfall`. Installed kubectl is v1.35.9;
  `kubectl version` warned that the two-minor client/server skew exceeds its
  supported range. Applied resources and server dry-run succeeded, but this
  tooling skew should be removed before relying on it beyond the local proof.
- Kubernetes: two API pods behind `api` Service; two web pods, each containing
  production-built Next.js and Nginx, behind `web` Service; one each of
  Sidekiq, Sidekiq outbox publisher, Kafka outbox publisher, Kafka audit
  consumer, Kafka projection consumer, closer and reconciliation scheduler.
  A one-shot `db-prepare` Job completed. No stateful dependency pod exists.
- External Compose: PostgreSQL, Redis, Kafka and Kafka topic initializer.
  The kind node joins `hammerfall_default`. The script generated selectorless
  Services/EndpointSlices for the current Compose IPs: `db:5432`,
  `redis:6379`, `kafka:9092`. Kafka's advertised `kafka:9092` resolved through
  the Kubernetes Service. A local Kubernetes Secret receives the Compose
  username/password through stdin; the values were not printed or committed.
- Web Service port-forward on loopback `8080` passed `/auctions` and `/api/v1`.
  The Nginx sidecar forwards API and Cable at runtime. Browser Cable behavior
  still needs a dedicated Session 2/3 exercise.

## Workload configuration

All nine application roles are Deployments; only API and web expose Services.
The [ExecPlan workload table](../plans/phase-18-execplan.md#workload-contracts)
records replicas, probes, resource requests/limits, shutdown contracts,
dependencies, scaling rules and residual limitations for every role. API
readiness queries PostgreSQL; `/up` is independent liveness. Web's two
containers each probe local HTTP. Background roles have process-exit restart,
no traffic-gating probe; logs/durable progress supply health evidence.
The proxy uses `/proxy-health` for its own liveness and `/` for readiness
through Next.js, so a Next.js outage does not restart a healthy proxy.
API has a 45-second grace, web and workers 30 seconds. Signal behavior under
active work is pending Session 2. No startup probe was needed in this observed
boot: first `/ready` attempts saw connection refused while Rails started, and
both pods then became Ready without liveness restarts. No HPA or PDB was added.

## Evidence

| Check | Actual result |
| --- | --- |
| Images | API image built from baked source; web `next build` compiled, typechecked and generated pages, then `next start` ran in the pod. Both were loaded into kind. |
| Manifests | `kubectl apply --dry-run=client/server -f k8s/base/` passed for all base resources; server dry-run of the Job passed. `bash -n k8s/local/up.sh` and `git diff --check` passed. |
| Focused source checks | Real-PostgreSQL `bundle exec rspec spec/requests/health_spec.rb`: 2 examples, 0 failures. Focused RuboCop: 3 files, no offenses. Focused Vitest subscription: 4 tests passed, including port 8080/3000 Cable fallback. Biome checked both changed frontend files; Next typegen/TypeScript passed. |
| Initial pod health | All 11 Deployment pods became Ready (13 containers: API 2, web 4, workers 7) with zero restarts. API EndpointSlice listed both pod IPs. Worker logs showed Redis jobs, outbox polls, Kafka audit/projection consumption, closer and scheduler startup. |
| Lifecycle | `API_BASE_URL=http://127.0.0.1:8080 ruby scripts/smoke-api` passed user/auction creation, scheduling, activation, two accepted bids, low-bid rejection, close/repeat close, post-close rejection and immutable history on auction 646. Direct SQL: `646|closed|11000|4109|4109|6|2` (id/status/price/leader/winner/revision/bid count). |
| Pod replacement | Deleted `api-5dd6cbbbb6-89rd5`. During deletion, 80/80 requests through the web proxy returned 200. Replacement `api-5dd6cbbbb6-hqvd2` became Ready and an API Endpoint; direct GET from that pod returned auction 646 closed, price 11000, revision 6, matching PostgreSQL. No reconstruction step. |
| Manual scale | Scaled API 2→3. New `api-5dd6cbbbb6-k9r42` became Ready and appeared in the EndpointSlice; direct GET returned the same auction state. Sixty GETs through the web proxy appeared in logs of all three API pods (26/13/21). Returned desired replicas to 2 afterward. |
| Local setup repeat | A full rerun built uniquely tagged images and rolled all Deployments to `phase18-20261002132005-650768`; `--no-build` reused that tag without Deployment changes and completed `db-prepare`. After correcting Secret byte handling, another full run rolled all Deployments to `phase18-20261002132852-683043`; the Job completed, all pods became Ready, and web/API/proxy liveness returned 200. These are reruns on the existing cluster, not a fresh-cluster recreation. |
| Secret byte audit | The initial `printenv` pipe stored an extra trailing newline. The script now uses `printf %s` inside the Compose DB container. A byte comparison of Compose environment and Kubernetes Secret passed without printing the password; the subsequent `db-prepare` Job and application rollout passed. |
| Logs and metrics | `kubectl logs` showed usable stdout for API/web/workers; no file log dependency. `kubectl top pods` returned `Metrics API not available`, so no CPU throttling or pod usage claim is made. |

## Invalid attempts and limits

- An initial web image build spent over two minutes recursively changing the
  entire dependency tree ownership. It was cancelled; the Dockerfile now
  assigns ownership to copied source and the generated `.next` directory only.
  The subsequent production build passed.
- `kind load` rejected the locally cached multi-platform `nginx:1.29-alpine`
  archive with a missing content digest. API and web images loaded separately;
  the kind node pulled Nginx itself and both web pods became Ready. The setup
  script no longer tries to load the cached Nginx archive.
- An edit to `up.sh` while an earlier invocation was in progress made that
  invocation exit 127. The finished script was rerun unchanged with
  `--no-build` and completed successfully; the script did not corrupt data.
- The first local Secret captured `printenv`'s newline after the password.
  A byte audit caught it despite successful DB queries. The generator now
  preserves the environment value exactly; a fresh Job and rollout passed.
- The proof shares the Compose development database, one Kafka broker and one
  Kubernetes node. It does not establish production Rails configuration,
  capacity, high availability, browser Cable recovery, active SIGTERM behavior,
  worker restart semantics or rolling-update compatibility. Those remain in
  the ExecPlan for later fresh sessions.
