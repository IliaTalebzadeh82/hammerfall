# hot — p14-20261001T135902Z-8aa52575

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T13:59:09.042817+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:19:02.398065Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh hot-auction <ignored manifest> 32 20s docs/benchmarks/p14-20261001T135902Z-8aa52575-hot`; achieved VUs: 32.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2018 | 294.85 ms | 392.24 ms | 436.86 ms |
| Bid HTTP duration | 1009 | 310.68 ms | 403.01 ms | 466.06 ms |

Achieved request rate: 98.55/s; iterations: 1009; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1070 |
| Accepted mutations | 61 |
| Domain rejections | 948 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 61 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.13%, memory 153.9MiB / 30.32GiB.
- During: PostgreSQL 12 sessions, 2 active, 1 lock waiters; fixture Sidekiq/Kafka pending 1/3; API CPU 104.09%, memory 156.9MiB / 30.32GiB.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.04%, memory 153.6MiB / 30.32GiB.
- Auction lock wait / place_bid: 1009 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 25.00 ms, 50.00 ms.
- Bid processing / accepted: 61 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Bid processing / rejected: 948 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 50.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 63 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 63 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
