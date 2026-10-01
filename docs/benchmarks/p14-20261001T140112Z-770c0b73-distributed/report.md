# distributed — p14-20261001T140112Z-770c0b73

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T14:01:20.031851+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 8 auction(s), 64 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:21:13.130781Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh distributed-auction <ignored manifest> 16 20s docs/benchmarks/p14-20261001T140112Z-770c0b73-distributed`; achieved VUs: 16.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 1600 | 177.26 ms | 239.87 ms | 276.02 ms |
| Bid HTTP duration | 800 | 195.47 ms | 248.77 ms | 285.44 ms |

Achieved request rate: 78.74/s; iterations: 800; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1390 |
| Accepted mutations | 590 |
| Domain rejections | 210 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 590 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.17%, memory 154MiB / 30.32GiB.
- During: PostgreSQL 12 sessions, 2 active, 0 lock waiters; fixture Sidekiq/Kafka pending 17/13; API CPU 106.51%, memory 156.2MiB / 30.32GiB.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.04%, memory 154.8MiB / 30.32GiB.
- Auction lock wait / place_bid: 800 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.
- Bid processing / accepted: 590 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Bid processing / rejected: 210 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 50.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 606 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 606 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
