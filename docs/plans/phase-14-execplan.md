# Phase 14 — Load Testing ExecPlan

Status: In progress; first milestone complete, hard checkpoint ready (2026-10-01).
Current milestone: Closing storm, WebSocket fanout, stepped saturation and deeper telemetry correlation in the next session.

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

Completed: Pinned k6 1.8.1 Docker harness and isolated public-API fixtures; normal/hot/duplicate scenarios; separate read-only warm-up; before/during/after environment, PostgreSQL and Prometheus capture; PostgreSQL invariant checker; per-run reports. Harness committed as `c86f4f8`. Primary telemetry-on runs and [benchmark index](../benchmarks/README.md) are stored. No API/domain code changed.
Verified: Focused Python/Bash/Ruby syntax, k6 live execution, Compose health, three primary HTTP load runs, and post-run authoritative checks passed. Primary normal: 4 VUs, 2,055 HTTP, 474 accepted mutations, p50/p95/p99 10.60/55.92/70.46 ms. Primary hot: 8 VUs, 1,519 bid attempts (370 accepted, 1,149 expected domain rejections), bid p50/p95/p99 62.33/96.42/114.94 ms, lock-wait p95 bucket ≤50 ms; zero unexpected errors. Primary duplicate: 8 VUs, 1 original, 2,381 replays, 125 intentional conflicts, one visible bid and no repeated revision/deadline effect; replay p50/p95/p99 6.62/13.09/20.55 ms. All primary database checks had zero failures.
Remaining: Implement and run closing storm (including real closer competition), 1,000-bidder attempt where feasible, WebSocket fanout, stepped load/saturation, repeated baseline/hot runs, post-lock trace analysis, publisher/pool correlation, small sabotage of checker/classifier, full backend/frontend/security/Compose/browser regression, hosted CI, final docs/learning guide/code map/journal/progress and adversarial review. Do not begin Phase 15.
Known failures/limitations: Initial normal result had `OTEL_ENABLED=false` despite observability containers running; retained as exploratory. First normal smoke had correlated operation/auction selection; fixed and reverified. One early hot export snapshot missed metric samples; capture now waits 20 seconds. The initial exploratory runs used an uncommitted harness and are not capacity evidence. The primary runs are short and below measured saturation; one during-run PostgreSQL sample may miss peaks. No queue-saturation, 1,000-bidder, WebSocket or closure claim. Host k6 command absent; pinned image works.
Relevant files: `load-tests/`, `apps/api/script/benchmark_verify.rb`, `docs/load-testing.md`, `docs/benchmarks/`, `docs/api.md`, `docker-compose.yml`.
Relevant ADRs: ADR-003 auction serialization, ADR-005 deadlines, ADR-006 idempotency.
Next-session starting point: Read `AGENTS.md`, latest handoff, Phase 14 spec and this plan. Start with closing-storm fixture/scenario and checker extensions, then fanout and stepped saturation. Use `load-tests/benchmark.sh` patterns, keep API `OTEL_ENABLED=true`, and put fresh manifests in ignored `load-tests/fixtures/`. Do not rerun the completed short runs without a concrete repeatability question.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Starting state | `git rev-parse HEAD`; `docker compose ps` | Phase 13 `44864cd`; API, DB, Redis, Kafka, web healthy | Initial inspection |
| Focused harness checks | `python3 -m py_compile load-tests/*.py`; `bash -n`; `ruby -c`; `git diff --check` | Passed | Terminal output; harness commit `c86f4f8` |
| Normal primary | `load-tests/benchmark.sh normal 4 30s` | 2,055 requests; 0 unexpected errors; 0 checker failures | [Report](../benchmarks/p14-20261001T133208Z-31a8c49a-normal/report.md) and adjacent raw/snapshots |
| Hot primary | `load-tests/benchmark.sh hot 8 30s` | 1,519 bids; 370 accepted/1,149 rejected; 0 unexpected errors; 0 checker failures | [Report](../benchmarks/p14-20261001T133320Z-03f35c6c-hot/report.md) and adjacent raw/snapshots |
| Duplicate primary | `load-tests/benchmark.sh duplicate 8 15s` | 2,381 replay/125 conflict/1 original; 1 bid; 0 checker failures | [Report](../benchmarks/p14-20261001T133436Z-1f8c4b84-duplicate/report.md) and adjacent raw/snapshots |
| Exploratory validation | Short k6 smokes; telemetry-on/off runs; hot export settlement check | Harness issues found and fixed; results retained with limitations | [Benchmark index](../benchmarks/README.md) |
| Pending gates | Closing/fanout/saturation; sabotage; broad regression, browser, hosted CI | Not run | Next milestone |
