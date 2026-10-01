# hot — p14-20261001T153137Z-407ec589

Recorded from commit `3dff3b7e953c9cd12a84af35231f6548da8c8f4c` at 2026-10-01T15:31:44.329783+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T15:51:38.144291Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh hot-auction <ignored manifest> 64 20s docs/benchmarks/p14-20261001T153137Z-407ec589-hot`; achieved VUs: 64.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2500 | 523.24 ms | 781.90 ms | 855.31 ms |
| Bid HTTP duration | 1250 | 540.94 ms | 795.70 ms | 883.05 ms |

Achieved request rate: 117.22/s; iterations: 1250; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1289 |
| Accepted mutations | 39 |
| Domain rejections | 1211 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 39 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 9 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.01%, memory 108.2MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- During: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 1/1; API CPU 116.25%, memory 123.6MiB / 30.32GiB; k6 CPU 16.12%, memory 47.32MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 113.4MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0, 'hammerfall.audit.v1': 1.0}; gauges are asynchronous and can be stale.
- Auction lock wait / place_bid: 1250 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 25.00 ms.
- Bid processing / accepted: 39 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 50.00 ms, 50.00 ms.
- Bid processing / rejected: 1211 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 50.00 ms, 50.00 ms.
- Publisher delivery / Kafka: 41 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 41 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
