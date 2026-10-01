# normal — p14-20261001T141516Z-7637fb67

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T14:15:23.617903+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 8 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:35:17.006458Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh normal-auction <ignored manifest> 4 30s docs/benchmarks/p14-20261001T141516Z-7637fb67-normal`; achieved VUs: 4.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 1922 | 12.45 ms | 68.53 ms | 81.61 ms |
| Bid HTTP duration | 296 | 56.89 ms | 78.44 ms | 86.49 ms |
| Maximum HTTP duration | 147 | 59.99 ms | 85.29 ms | 92.67 ms |

Achieved request rate: 63.85/s; iterations: 1479; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1922 |
| Accepted mutations | 443 |
| Domain rejections | 0 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 717 bid rows, 90 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.15%, memory 204.6MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 2.0, 'hammerfall.audit.v1': 2.0}; gauges are asynchronous and can be stale.
- During: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 12/7; API CPU 81.31%, memory 168.1MiB / 30.32GiB; k6 CPU 7.76%, memory 16.34MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 4.0, 'hammerfall.projection.v1': 2.0}; gauges are asynchronous and can be stale.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 165.3MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 2.0, 'hammerfall.projection.v1': 0.0}; gauges are asynchronous and can be stale.
- Auction lock wait / place_bid: 296 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.
- Bid processing / accepted: 296 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 459 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 459 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
