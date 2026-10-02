# Phase 18 — Kubernetes ExecPlan

Status: In progress; Session 1 milestone complete and checkpoint ready.
Current milestone: start a fresh Session 2 for active lifecycle/failure proof.
Completed: local kind strategy; ADR-014; immutable API/web images; API
readiness; namespace, config, Secret generation, external dependency Services,
all application Deployments, web runtime proxy and repeatable local setup.
Verified: [Session 1 report](../kubernetes/session-1.md) documents two ready API
pods, all background roles, lifecycle smoke, direct SQL, pod replacement, 80/80
served requests, 2→3 API scaling and all-three-pod routing. Focused checks pass.
Remaining: Session 2 active termination/retry, Sidekiq/publisher/consumer
shutdown, closer/scheduler replacement, rollout, scale-down, Cable and
resource behavior; then a fresh final session for remaining fixes, optional
bounded load, full regression, browser, fresh cluster, docs and hosted CI.
Known failures/limitations: kubectl 1.35 versus kind server 1.37 warns of
unsupported two-minor skew; no metrics-server, so `kubectl top` unavailable.
No serious correctness failure is currently known. Local values are not
production sizing. Startup probes were unnecessary in observed boots.
Relevant files: `k8s/`, `infrastructure/*-k8s.Dockerfile`, API health
controller/route/spec, frontend Cable fallback, ADR-014 and Session 1 report.
Relevant ADRs: [ADR-001](../adr/001-modular-monolith.md),
[ADR-010](../adr/010-transactional-public-outbox.md),
[ADR-011](../adr/011-kafka-domain-events.md),
[ADR-014](../adr/014-local-kubernetes-process-orchestration.md).
Next-session starting point: fresh Codex conversation; read AGENTS, handoff,
this plan, Phase 18 spec and [Session 1 report](../kubernetes/session-1.md).
Keep Compose application containers stopped and external dependencies running;
start with active API SIGTERM and same-key ambiguity through the web proxy.

## Decisions

- Use one kind cluster because it is installed. PostgreSQL, Redis and Kafka
  remain in Compose, outside Kubernetes. Connect the kind node to the Compose
  network and create selectorless Kubernetes Services with generated
  EndpointSlices for the current container addresses. Kafka's advertised
  `kafka:9092` resolves to the Kubernetes Service name inside pods.
- Use one namespace, `hammerfall`; plain YAML and one local setup script.
  Generate only the development Secret and dependency endpoints at runtime.
- API has two replicas. The closer and scheduler have one for operational
  economy; PostgreSQL locking and leases still own correctness. Other worker
  roles start at one and can be scaled only after role-specific evidence.
- No HPA initially: manual scale is the proof, and no metrics-server target or
  database connection budget has been validated. No PDB initially: a local
  single-node cluster would not demonstrate voluntary-disruption availability.
- Build code into distinct API and web images. Run Rails with frozen local
  development configuration against the existing demo database; this is a
  local orchestration proof, not a production Rails configuration claim. Use
  `next build`/`next start` for web. A web proxy sidecar routes `/api` and
  `/cable` to the API Service at runtime so the image has no cluster address.

## Workload contracts

All requests/limits below are initial local values, subject to observed pod
usage. An absent worker probe is deliberate: Deployments restart exited
processes; these workers have no HTTP traffic to gate. Their dependency and
progress contracts must be checked with job/offset/outbox evidence.

| Workload | Primitive / replicas | Readiness | Liveness | Request / limit (CPU, memory) | Shutdown | Shared dependencies / scaling | Failure or restart result / decision / limitation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| API | Deployment + Service / 2 | DB query; no Redis/Kafka check | Rails `/up` | 250m, 384Mi / 1, 1Gi | Puma TERM, 45s grace | PG, Redis for Cable; manual 2→3 | Replacement PASS; active SIGTERM INCONCLUSIVE / no capacity claim |
| Web | Deployment + Service / 2 | local HTTP | local HTTP | 100m, 128Mi / 500m, 512Mi | Node and proxy TERM, 30s | API Service; stateless | Startup PASS; replacement INCONCLUSIVE / local proxy only |
| Sidekiq | Deployment / 1 | running; no traffic gate | process exit | 100m, 256Mi / 500m, 768Mi | Sidekiq TERM, 30s | PG, Redis; bounded concurrency 2 | Startup PASS; active restart INCONCLUSIVE / at-least-once jobs |
| Sidekiq publisher | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Redis; row claims permit N | Startup PASS; active restart INCONCLUSIVE / duplicate enqueue possible |
| Kafka publisher | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Kafka; row claims permit N | Startup PASS; active restart INCONCLUSIVE / duplicate publish possible |
| Kafka audit consumer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM, close consumer, 30s | PG, Kafka; group partitions bound N | Consumption PASS; rebalance INCONCLUSIVE / replay expected |
| Kafka projection consumer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM, close consumer, 30s | Redis, Kafka; revision guard permits N | Consumption PASS; rebalance INCONCLUSIVE / replay expected |
| Auction closer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG; multiple safe under lock but not needed | Startup PASS; replacement INCONCLUSIVE / polling lag |
| Reconciliation scheduler | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Redis; lease permits overlap | Enqueue PASS; replacement INCONCLUSIVE / lease expiry delay |

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Tooling | `kind version`, `docker info`, `kubectl config current-context` | kind/Docker present; no context | Session 1 inspection |
| Image builds | `docker build -f infrastructure/{api,web}-k8s.Dockerfile` | PASS; Next production compile/typecheck | [Session 1](../kubernetes/session-1.md) |
| Manifest validation | `kubectl apply --dry-run=client/server -f k8s/base/` plus Job | PASS | [Session 1](../kubernetes/session-1.md) |
| Focused source checks | Health RSpec, RuboCop, Vitest, Biome, TypeScript | PASS; 2 RSpec/4 Vitest | [Session 1](../kubernetes/session-1.md) |
| Two API pods and basic lifecycle | `up.sh`, web port-forward, `scripts/smoke-api`, direct SQL | PASS; all roles Ready, auction 646 closed correctly | [Session 1](../kubernetes/session-1.md) |
| API deletion/replacement | Delete one pod during 80 GETs, inspect new pod and SQL | PASS; 80/80 200, replacement revision 6 | [Session 1](../kubernetes/session-1.md) |
| API manual scale | `kubectl scale` 2→3, 60 GETs and logs | PASS; 26/13/21 requests across three pods | [Session 1](../kubernetes/session-1.md) |
| Setup rerun | Full unique-tag build/rollout, `--no-build`, final corrected-Secret rollout | PASS; latest tag on all Deployments, Job complete, all Ready | [Session 1](../kubernetes/session-1.md) |
| Secret byte audit | Compare Compose env bytes to Kubernetes Secret without printing value | PASS after newline correction | [Session 1](../kubernetes/session-1.md) |
| Lifecycle/failure campaign | Pending | INCONCLUSIVE | Session 2 |
| Final regression and security | Pending | INCONCLUSIVE | Final session |
