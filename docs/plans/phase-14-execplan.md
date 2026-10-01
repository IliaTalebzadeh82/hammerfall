# Phase 14 — Load Testing ExecPlan

Status: In progress (2026-10-01).
Current milestone: Methodology, k6 harness, deterministic fixtures, normal/hot/duplicate runs and authoritative checks.

## Protocol

- Use the unchanged Phase 13 Compose configuration and observability stack for the primary local comparison. Record exact Git SHA, UTC time, host and Docker/k6 versions, CPU/RAM, container limits and service settings for each retained run. This shared host is a comparative local test, not a production capacity estimate.
- Create isolated benchmark users and auctions with a unique run label; record their IDs and configuration in a manifest. Do not reset or delete unrelated data. Use fixed random seeds/workload proportions and explicitly record VUs, duration, achieved iterations, dropped iterations and generator CPU/memory. Warm each fixture with a short, separate low-load run; retain cold-start observations separately if interesting.
- Run at increasing documented load levels. Keep telemetry enabled for primary measurements. Store machine output separately from concise result reports under `docs/benchmarks/`. Report p50/p95/p99 only with sample counts; classify accepted, domain rejection, replay, conflict, client error, server error and timeout separately. Bounded metric tags only.
- Take before/after observations of PostgreSQL sessions and locks, API/worker CPU and memory, pool/lock metrics, outbox backlog/oldest age, Kafka lag and reconciliation. Sample diagnostics sparingly. Distinguish generator, host, container, application and database limitations.
- After mutation runs, independently query PostgreSQL to verify sequence uniqueness/order, price/leader against history, winner if closed, maximum ceilings, revision/outbox consistency and duplicate command effects. Do not infer correctness from HTTP alone.
- Retain all meaningful runs, including failed attempts. Repeat representative baseline and hot runs before a bottleneck conclusion. Do not tune application configuration or declare SLO/capacity from these runs.

## Decisions

- Benchmark fixtures use the demo identity model and current HTTP contract. Fixture labels allow scoped cleanup; fixture data stays distinct from result documents.
- The first milestone uses the existing Compose stack. Closing storm, WebSocket fanout and saturation belong to the next milestone after a hard checkpoint if substantial work remains.

## Progress

Completed: Phase 13 handoff and Phase 14 scope reviewed; initial methodology defined.
Verified: None yet.
Remaining: Implement harness/fixtures/checker; run focused and live scenarios; closing storm, 1000-bidder challenge where feasible, fanout, repetitions, analysis, sabotage, broad regression, docs and hosted CI.
Known failures/limitations: k6 is not installed on the host; select and pin a container image. Existing Compose services are running but need a health/config baseline before load.
Relevant files: `load-tests/`, `docs/load-testing.md`, `docs/benchmarks/`, `docs/api.md`, `docker-compose.yml`, API auction/bid/idempotency code.
Relevant ADRs: ADR-003 auction serialization, ADR-005 deadlines, ADR-006 idempotency.
Next-session starting point: Read this plan and the latest handoff; follow its current milestone and Evidence Index.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Starting state | `git rev-parse HEAD`; `docker compose ps` | `44864cd`; services running (health baseline pending) | Phase 13 final commit |
