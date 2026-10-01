# Phase 15 — Performance Engineering ExecPlan

Status: Active — Session 1 profiling milestone complete; hard checkpoint pending.
Current milestone: Session 1 evidence and instrumentation are complete. Next session begins controlled diagnostic-overhead and concurrency experiments, one variable at a time.

## Protocol and decisions

- Use the retained [Phase 14 evidence](../benchmarks/README.md) as the baseline. Keep workload, observability and runtime settings fixed within each comparison; disclose shared-host variance and sample counts. Run the authoritative PostgreSQL checker after mutation load.
- Measure pre-Rack admission only with a supported server-side signal. A Rack start timestamp is the beginning of observed app time, not an admission timestamp. Measure DB checkout separately from auction-lock wait.
- Store raw profiles and per-run snapshots under `docs/benchmarks/`. Keep recorded output bounded and free of private command keys, maximum bids and secrets.
- Tune one variable at a time only after its bottleneck has direct evidence. Require repeatable before/after improvement and correctness verification before adoption. Do not alter the auction concurrency or publication protocol merely for throughput.

## Hypothesis ledger

| Hypothesis | Phase 14 evidence | Missing measurement / method | Result | Proposed experiment | Before → change → after → correctness | Decision |
|---|---|---|---|---|---|---|
| Puma admission contributes to ~935 ms hot HTTP p95 | One-row throughput flattened at 84–101/s; lock p95 ≤25 ms | Puma 8.0.2 control stats and Rack-boundary limitation | 64 VUs: backlog median 58, capacity median 0, three threads; HTTP p95 782 ms. No exact per-request pre-Rack timer. | Isolated Puma thread experiment after diagnostic overhead pair | 117.22/s, p95 781.90 ms → pending → pending → checker pending | Supported contributor; tuning deferred |
| DB checkout wait contributes | Pool 3; checkout unmeasured | Instrument checkout and actual blocking queue poll; sample pool state | 5,133 checkouts ≤1 ms; no blocking-wait samples in hot run | No pool-size change unless a later workload shows waits | Baseline measured → no change → no after; hot checker passed | Reject as current dominant cause |
| Ruby CPU/allocation dominates post-admission time | API used roughly one CPU core; RSS ~130→200 MiB plateau | StackProf CPU samples, GC counters, RSS before/during/after | Development file watcher 13.3% inclusive CPU; GC 5.24%; 5.07M allocations/20s; RSS nonmonotonic | Isolated development-reloader diagnostic; longer memory observation | Profiled 102.58/s, p95 959.76 ms → no tuning → pending; checker passed | File watcher confirmed local cost; leak inconclusive |
| Query cost or proxy resolution is material | Domain processing far below HTTP p95; path breakdown missing | Isolated real-PG Rack query categories and timing | Warm stale 15 queries/3.29 ms SQL; proxy 22/7.03 ms; replay 5/0.96 ms; no identified slow query | No index/proxy change absent new evidence | Probe only → no change → no after; statuses checked | Reject as current dominant cause |
| 1,024 FD ceiling reflects concurrent sockets rather than leak | 1,000 contenders caused 28 EMFILE and 64 timeouts; 600 clean | API FD type/count and cleanup across hot/fanout | 200 subscribers: 226 FDs, 202 HTTP sockets; 20 before/23 after | Isolated raised-limit diagnostic later | Baseline measured → no change → pending; fanout checker passed | Socket pressure supported; leak not seen in short run |
| Cable handshake shares admission/FD pressure | 500 connected; handshake p95 ~2s; no socket failures | Puma and FD measurements during fanout | 200 subscribers: handshake p95 847 ms, backlog peak 190, 202 HTTP sockets; Redis/CPU contribution unisolated | Examine after admission experiment if relevant | Baseline measured → no change → pending; 200/200 confirmed, checker passed | Admission plausible; primary cause inconclusive |
| Publisher/telemetry adds material request cost | Publisher durations bounded; telemetry on/off pair unstable | Profile only if hot path indicates cost; controlled on/off pair if useful | Pending | Preserve observability absent meaningful gain | Pending | Deferred |

## Progress

Completed: Environment pinned; opt-in DB checkout/pool metrics and private Puma stats socket; CPU/GC, SQL-path and runtime/FD samplers; 64-VU hot run with and without CPU profiling; 200-subscriber fanout; [causal report](../benchmarks/phase-15-session-1.md). No performance configuration or auction rule change was adopted. Three retained live run checkers passed.
Verified: Focused 51 RSpec examples (0 failures), targeted RuboCop (8 files, 0 offenses), Ruby/Bash/Python syntax and profiler smoke; hot and fanout PostgreSQL checkers passed. The diagnostic socket mode is 0600 under a 0700 directory. Privacy scan found no listed raw key, maximum, origin or credential fields in new retained text artifacts.
Remaining: Repeated same-code diagnostic on/off comparison; controlled one-variable Puma and, only if warranted, DB/FD experiments; longer memory/allocation follow-up; accepted-work and resource economics; after-change correctness/sabotage as relevant; final broad backend/web/security, Compose/browser and hosted CI gates; final performance report and adversarial review.
Known failures/limitations: Puma pre-Rack per-request admission time is not exposed by this setup; queue-length/rate is an estimate, not a percentile. CPU profiling changes run behavior; diagnostic overhead has not been isolated. Short RSS/FD observations do not prove no slow leak. No production-capacity result. No serious correctness failure observed.
Relevant files: `docker-compose.yml`, `apps/api/config/puma.rb`, `apps/api/lib/observability/`, `apps/api/script/performance_sample.rb`, `apps/api/script/query_profile.rb`, `load-tests/benchmark.sh`, `load-tests/capture.py`, `docs/benchmarks/phase-15-session-1.md`.
Relevant ADRs: ADR-003 auction serialization, ADR-005 deadlines, ADR-006 idempotency.
Next-session starting point: Read this plan, latest handoff, Phase 15 spec and [Session 1 report](../benchmarks/phase-15-session-1.md). First run a repeated same-build, same-workload diagnostic-on/off pair. Then test Puma threads alone with pool fixed at 3, provided the control comparison supports the baseline. Record p50/p95/p99, accepted work, backlog, DB checkout/lock, CPU/RSS and checker per run. Do not stack pool or FD changes.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Phase 14 baseline | Retained 64-VU hot run and final review | HTTP p95 ~935 ms, lock p95 ≤25 ms bucket; checker passed | [Phase 14 final review](../benchmarks/phase-14-final.md) |
| Repository starting state | `git status --short` | Clean | Kickoff inspection |
| Pinned runtime | Puma control stats; `docker compose exec api`; Compose snapshot | One process/3 threads/pool 3; soft/hard FD 1,024/524,288; Ruby 4.0.6, Rails 8.1.3.1, PG 18.6 | [Session 1 report](../benchmarks/phase-15-session-1.md) |
| Diagnostic hook tests | `docker compose exec -T -e RAILS_ENV=test -e REDIS_URL=redis://redis:6379/15 api bundle exec rspec spec/lib/observability_spec.rb spec/requests/bids_spec.rb spec/requests/maximum_bids_spec.rb spec/requests/idempotency_spec.rb` | 51 examples, 0 failures, seed 10018 | Focused terminal result |
| Targeted lint and syntax | RuboCop on 8 changed Ruby files; `bash -n`; `python3 -m py_compile`; `ruby -c`; `git diff --check` | 8 files, no offenses; syntax/diff checks passed | Focused terminal results |
| Hot admission/checkout | `PROFILE_RUNTIME=true load-tests/benchmark.sh hot 64 20s` | 2,500 HTTP; 117.22/s; p95 781.90 ms; 39 accepted mutations; checkout ≤1 ms; no blocking pool wait; Puma backlog median 58; checker 0 failures | [Run](../benchmarks/p14-20261001T153137Z-407ec589-hot/report.md), runtime and snapshots |
| CPU/GC/allocations | `PROFILE_RUNTIME=true PROFILE_CPU=true load-tests/benchmark.sh hot 64 20s`; StackProf CPU | 20,075 samples; file watcher 13.3% inclusive, GC 5.24%; 5.07M allocated objects; checker 0 failures | [Run](../benchmarks/p14-20261001T153701Z-0474034d-hot/report.md), compressed dump and GC counters |
| Real-PG query paths | `docker compose exec -T api bin/rails runner script/query_profile.rb` | Seven observations across accepted, stale, maximum, proxy and replay paths; expected statuses; warm SQL totals 0.96–13.42 ms | [Sanitized query profile](../benchmarks/phase-15-query-profile.json) |
| FD/Cable | `PROFILE_RUNTIME=true load-tests/benchmark.sh fanout 200 20s` | 200/200 confirmed, 5,800 k6 invalidations, peak 226 FDs/202 HTTP sockets, 20→23 after, checker 0 failures | [Run](../benchmarks/p14-20261001T154218Z-e0ba815f-fanout/report.md) |
| Privacy scan | `rg` for credentials, raw keys, maxima, priority and origin in new text artifacts | No matches | Session 1 review |
