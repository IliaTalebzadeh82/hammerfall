# normal — p14-20261001T132051Z-129892c8

Recorded from commit `44864cd360b3af0dd65d8ca5e5ac6f0db554e07b` at 2026-10-01T13:20:57.890139+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=false.
- Fixture: 8 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:40:51.092164Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh normal-auction <ignored manifest> 4 30s docs/benchmarks/p14-20261001T132051Z-129892c8-normal`; achieved VUs: 4.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2018 | 10.62 ms | 60.10 ms | 77.23 ms |
| Bid HTTP duration | 310 | 49.11 ms | 75.50 ms | 96.00 ms |
| Maximum HTTP duration | 155 | 49.76 ms | 76.92 ms | 96.93 ms |

Achieved request rate: 67.14/s; iterations: 1553; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 2018 |
| Accepted mutations | 465 |
| Domain rejections | 0 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 757 bid rows, 89 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.02%, memory 116.4MiB / 30.32GiB.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.02%, memory 116.4MiB / 30.32GiB.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.

Exploratory telemetry-off comparison, executed while the harness was uncommitted. The observability containers were running, but API OTEL_ENABLED was false. Retained to expose the setup error; do not infer instrumentation overhead from this one unmatched run.
