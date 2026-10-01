# hot — p14-20261001T133320Z-03f35c6c

Recorded from commit `c86f4f81511d796593a4aea57bb6689ca4f64a65` at 2026-10-01T13:33:27.453501+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:53:20.886391Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh hot-auction <ignored manifest> 8 30s docs/benchmarks/p14-20261001T133320Z-03f35c6c-hot`; achieved VUs: 8.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 3038 | 52.23 ms | 88.94 ms | 107.64 ms |
| Bid HTTP duration | 1519 | 62.33 ms | 96.42 ms | 114.94 ms |

Achieved request rate: 100.83/s; iterations: 1519; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1889 |
| Accepted mutations | 370 |
| Domain rejections | 1149 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 370 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.05%, memory 118.5MiB / 30.32GiB.
- During: PostgreSQL 11 sessions, 2 active, 0 lock waiters; fixture Sidekiq/Kafka pending 4/7; API CPU 101.85%, memory 119.5MiB / 30.32GiB.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.04%, memory 118MiB / 30.32GiB.
- Auction lock wait / place_bid: 1519 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 50.00 ms, 50.00 ms.
- Bid processing / accepted: 370 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 50.00 ms, 100.00 ms.
- Bid processing / rejected: 1149 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 372 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 372 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.

All 1,519 bid attempts targeted one auction. The 370 accepted bids and 1,149 stale/domain rejections are distinct from the zero unexpected failures. Lock-wait p95 fell in the ≤50 ms bucket, while HTTP bid p95 was 96.42 ms; this does not by itself isolate post-lock processing or prove the row lock dominates. A single during-run API CPU sample was 101.85% of one core; 4 Sidekiq and 7 Kafka outbox rows were pending then, and drained afterward. Compare lock and processing traces at higher steps before assigning a bottleneck.
