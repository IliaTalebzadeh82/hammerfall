# burst — p14-20261001T141653Z-988dbc9b

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T14:17:01.956782+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 1 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:36:53.176937Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh duplicate-burst <ignored manifest> 64 5s docs/benchmarks/p14-20261001T141653Z-988dbc9b-burst`; achieved VUs: see summary.json.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 128 | 52.71 ms | 332.99 ms | 350.35 ms |
| Bid HTTP duration | 128 | 52.71 ms | 332.99 ms | 350.35 ms |
| Replay HTTP duration | 127 | 53.09 ms | 333.12 ms | 350.36 ms |

Achieved request rate: 138.09/s; iterations: 64; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1 |
| Accepted mutations | 1 |
| Domain rejections | 0 |
| Idempotent replays | 127 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 1 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Simultaneous first-wave and delayed replay latency are in `summary.json` under `benchmark_burst_initial_duration` and `benchmark_burst_later_duration`; the former mixes original ownership with concurrent idempotency waiters.
- Before: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 165.3MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 2.0, 'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- During: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.31%, memory 165.5MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 2.0, 'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.15%, memory 165.5MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 2.0, 'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- Auction lock wait / place_bid: 1 observed histogram samples; too few for useful percentile reporting.
- Bid processing / accepted: 1 observed histogram samples; too few for useful percentile reporting.
- Publisher delivery / Kafka: 1 observed histogram samples; too few for useful percentile reporting.
- Publisher delivery / Sidekiq: 1 observed histogram samples; too few for useful percentile reporting.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
