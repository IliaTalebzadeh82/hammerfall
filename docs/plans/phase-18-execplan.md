# Phase 18 — Kubernetes ExecPlan

Status: In progress; Session 2 live-failure milestone complete and checkpoint ready.
Current milestone: start a fresh final session for completion gates and review.
Completed: local kind strategy; ADR-014; immutable API/web images; API
readiness; namespace, config, Secret generation, external dependency Services,
all application Deployments, web runtime proxy and repeatable local setup.
Verified: [Session 1](../kubernetes/session-1.md) proves startup, lifecycle,
replacement and initial scaling. [Session 2](../kubernetes/session-2.md)
proves bounded active API termination/retry, post-commit lost response,
API/web rollouts, scale-down, async pod replacement and durable catch-up,
Kafka rebalance, closer/scheduler replacement, browser Cable recovery and
cgroup resource snapshot.
Remaining: final adversarial review and any repairs; optional bounded load;
full regression, lint/security/build gates, fresh cluster setup, final
browser/runtime verification, documentation and hosted CI.
Known failures/limitations: kubectl 1.35 versus kind server 1.37 warns of
unsupported two-minor skew; no metrics-server, so `kubectl top` unavailable.
No serious correctness failure is currently known. Long active worker
interruption and production capacity are unproven. Local values are not
production sizing. Startup probes were unnecessary in observed boots.
Relevant files: `k8s/`, `infrastructure/*-k8s.Dockerfile`, API health
controller/route/spec, frontend Cable fallback and browser harness, ADR-014,
and Session 1/2 reports.
Relevant ADRs: [ADR-001](../adr/001-modular-monolith.md),
[ADR-010](../adr/010-transactional-public-outbox.md),
[ADR-011](../adr/011-kafka-domain-events.md),
[ADR-014](../adr/014-local-kubernetes-process-orchestration.md).
Next-session starting point: fresh Codex conversation; read AGENTS, handoff,
this plan, Phase 18 spec and [Session 2 report](../kubernetes/session-2.md).
Keep Phase 19 gated. Inspect the current diff and finish final verification.
The kind cluster is running with desired replicas restored. The web
port-forward is an ephemeral terminal session and may need restarting.

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
| API | Deployment + Service / 2 | DB query; no Redis/Kafka check | Rails `/up` | 250m, 384Mi / 1, 1Gi | Puma TERM, 45s grace | PG, Redis for Cable; manual 2→3 | Active bounded SIGTERM, lost-response replay, rollout, scale-down PASS / no capacity claim |
| Web | Deployment + Service / 2 | local HTTP | local HTTP | 100m, 128Mi / 500m, 512Mi | Node and proxy TERM, 30s | API Service; stateless | Rolling restart 100/100 reads PASS / local proxy only |
| Sidekiq | Deployment / 1 | running; no traffic gate | process exit | 100m, 256Mi / 500m, 768Mi | Sidekiq TERM, 30s | PG, Redis; bounded concurrency 2 | Replacement/catch-up PASS; in-flight job death untested / at-least-once jobs |
| Sidekiq publisher | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Redis; row claims permit N | Replacement/catch-up PASS; in-flight death untested / duplicate enqueue possible |
| Kafka publisher | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Kafka; row claims permit N | Replacement/catch-up PASS; in-flight death untested / duplicate publish possible |
| Kafka audit consumer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM, close consumer, 30s | PG, Kafka; group partitions bound N | Replacement and 1→2→1 rebalance PASS / replay expected |
| Kafka projection consumer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM, close consumer, 30s | Redis, Kafka; revision guard permits N | Replacement and 1→2→1 rebalance PASS / replay expected |
| Auction closer | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG; multiple safe under lock but not needed | Replacement closed two due auctions PASS / polling lag |
| Reconciliation scheduler | Deployment / 1 | running | process exit | 50m, 128Mi / 500m, 512Mi | TERM trap, 30s | PG, Redis; lease permits overlap | Replacement enqueued/completed scans PASS / forced lease-holder death untested |

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
| Lifecycle/failure campaign | Active API TERM/crash, rollouts, worker replacement, rebalance, Cable, resources | PASS within stated limits | [Session 2](../kubernetes/session-2.md) |
| Cable harness lint and syntax | Biome check, `node --check` | PASS | Session 2 |
| Final regression and security | Pending | INCONCLUSIVE | Final session |
