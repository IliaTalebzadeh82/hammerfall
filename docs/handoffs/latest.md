# Current handoff — Phase 18 Session 1 checkpoint

Updated: 2026-10-02. Phase 18 — Kubernetes is in progress, explicitly
authorized. Session 1 implementation and basic local proof are complete;
begin a fresh Codex conversation for Session 2. Do not start Phase 19. Read
the [Phase 18 ExecPlan](../plans/phase-18-execplan.md),
[specification](../phases/phase-18.md) and
[Session 1 report](../kubernetes/session-1.md); use the
[context map](../context-map.md) for targeted source. Phase 17's
[final report](../multi-instance/phase-17-final.md) remains the multi-instance
correctness baseline.

Local kind v0.33.0 runs one Kubernetes v1.37 node and namespace `hammerfall`.
Two API pods behind a Service, two production-built web pods behind a web
Service/Nginx sidecar, and one each of seven background roles run in
Deployments. A `db-prepare` Job completed. PostgreSQL, Redis and Kafka stay in
Compose; the kind node joins the Compose network and selectorless Services with
generated EndpointSlices point to the external containers. The database
username/password are generated into a local Kubernetes Secret, never
committed. [ADR-014](../adr/014-local-kubernetes-process-orchestration.md)
records this boundary; [local setup](../../k8s/README.md) documents the
commands. Rails uses frozen local development configuration; no production
Rails or cloud deployment is claimed.

API `/ready` queries PostgreSQL and gates Service membership; `/up` remains
process liveness independent of Redis/Kafka. Both API pods became Ready after
initial boot-time probe failures. All 11 application pods were Ready with zero
restarts. Focused health RSpec (2 examples), frontend Vitest (4 tests),
RuboCop, Biome/TypeScript, image builds, YAML server dry-run and repeated local
setup passed. A lifecycle smoke through the web proxy created and closed
auction 646; direct SQL confirmed its price, winner, revision and two bids.
Deleting one API pod during 80 requests yielded 80 HTTP 200s; its replacement
immediately read the current auction. Manual API scale 2→3 made the new pod
Ready, and 60 requests reached all three (26/13/21). Desired replicas returned
to two. Exact observations and invalid setup attempts are in Session 1.

Next: prove active API SIGTERM and ambiguous same-key retry; rolling update,
graceful scale-down and Cable socket replacement; Sidekiq and publisher
termination; Kafka consumer rebalance; closer and scheduler replacement; and
resource behavior. Then checkpoint. A later fresh final session owns remaining
repairs, optional bounded load, full regression, browser and fresh-cluster
checks, documentation/security review and hosted CI. Kubectl 1.35.9 versus
server 1.37.0 warns of unsupported version skew, and no metrics-server is
installed; `kubectl top` is unavailable. No serious correctness failure is
currently known, but active lifecycle semantics remain unverified.
