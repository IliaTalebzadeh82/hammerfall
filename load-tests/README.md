# Phase 14 k6 harness

The fixture creator uses the public demo HTTP API and creates new labeled users
and auctions for each run. It never deletes other data. The manifest records IDs,
fixed terms and the duplicate command key. Fixtures are not benchmark results.

Run the observability Compose profile and ensure all dependencies are healthy.
Use pinned `grafana/k6:1.8.1` (Docker image digest at initial pull:
`sha256:23f2279054c3e01535455c4d92914a625df12aeb631ea0e3ea7a43f96bcbc843`).
The container uses host networking, so `http://127.0.0.1:3001` is the API.

For retained measurements, use the orchestrator. It creates a fresh fixture,
runs the read-only warm-up, captures before/during/after environment and
telemetry, waits for exporter settlement, verifies PostgreSQL state and writes
`report.md` beside the raw result. It requires API `OTEL_ENABLED=true` by
default and fails on unexpected client/server/transport errors or timeouts.

```bash
load-tests/benchmark.sh normal 4 30s
load-tests/benchmark.sh hot 8 30s
load-tests/benchmark.sh duplicate 8 15s
```

Use distinct fixtures for each step and repetition. Set `REQUIRE_OTEL=false`
only for a clearly labeled instrumentation comparison. The lower-level
commands below are useful for harness validation and targeted experiments.

```bash
python3 load-tests/prepare.py --scenario normal --auctions 8 --users 32 \
  --minutes 20 --output load-tests/fixtures/normal.json
load-tests/run.sh normal-auction load-tests/fixtures/normal.json 4 30s \
  docs/benchmarks/example-normal

python3 load-tests/prepare.py --scenario hot --auctions 1 --users 32 \
  --minutes 20 --output load-tests/fixtures/hot.json
load-tests/run.sh hot-auction load-tests/fixtures/hot.json 4 30s \
  docs/benchmarks/example-hot

python3 load-tests/prepare.py --scenario duplicate --auctions 1 --users 1 \
  --minutes 20 --output load-tests/fixtures/duplicate.json
load-tests/run.sh duplicate-retries load-tests/fixtures/duplicate.json 8 15s \
  docs/benchmarks/example-duplicate
```

Copy the exact manifest JSON into `BENCHMARK_MANIFEST` for authoritative checks:

```bash
docker compose exec -T -e "BENCHMARK_MANIFEST=$(cat load-tests/fixtures/hot.json)" \
  api bin/rails runner script/benchmark_verify.rb
```

The 10-slot normal workload is 50% auction reads, 20% history reads, 20% manual
bids and 10% maximum bids. Mutating iterations first read PostgreSQL state and
offer its current price plus one increment (four for a maximum). Concurrent
state changes can produce expected 422 responses. The hot workload sends every
VU to one auction with a fresh command key. The duplicate workload sends every
VU the same actor, auction and key: 19 of each 20 iterations replay the exact
amount; one conflicts intentionally. A brief sleep on every fifth iteration
adds delayed retries. The generator counts accepted, rejected, replay, conflict,
client/server error and timeout separately. `http_req_failed` uses expected
200/201/409/422 statuses; inspect the custom outcome counts for semantics.

Use a distinct fixture for each step and repeat. Store `summary.json`, the full
`k6.log`, environment/configuration, database verification, telemetry snapshots
and a concise interpretation in the retained result directory. Important runs
need a small, separate read-only warm-up; record it explicitly. Compare only
runs with the same configuration, and report achieved rather than requested
load. This is a shared local host, not a production capacity claim. See
[`docs/plans/phase-14-execplan.md`](../docs/plans/phase-14-execplan.md).
