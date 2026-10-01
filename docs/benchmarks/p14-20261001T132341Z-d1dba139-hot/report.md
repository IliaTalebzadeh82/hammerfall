# hot — p14-20261001T132341Z-d1dba139

Recorded from commit `44864cd360b3af0dd65d8ca5e5ac6f0db554e07b` at 2026-10-01T13:23:48.176728+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:43:41.486947Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh hot-auction <ignored manifest> 8 30s docs/benchmarks/p14-20261001T132341Z-d1dba139-hot`; achieved VUs: 8.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2636 | 63.66 ms | 111.65 ms | 136.94 ms |
| Bid HTTP duration | 1318 | 75.54 ms | 121.69 ms | 148.83 ms |

Achieved request rate: 87.39/s; iterations: 1318; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1630 |
| Accepted mutations | 312 |
| Domain rejections | 1006 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 312 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 110.8MiB / 30.32GiB.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.12%, memory 111.4MiB / 30.32GiB.
- Auction lock wait / place_bid: 1189 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 50.00 ms, 50.00 ms.
- Bid processing / accepted: 281 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Bid processing / rejected: 907 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 314 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 314 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.

Exploratory hot run with an uncommitted harness. The first after snapshot missed a material fraction of exported bid metrics, so histogram deltas are incomplete. Do not use its lock percentiles for a bottleneck conclusion.
