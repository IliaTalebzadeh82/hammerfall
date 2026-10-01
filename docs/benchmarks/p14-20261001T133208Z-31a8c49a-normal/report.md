# normal — p14-20261001T133208Z-31a8c49a

Recorded from commit `c86f4f81511d796593a4aea57bb6689ca4f64a65` at 2026-10-01T13:32:15.821492+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 8 auction(s), 32 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:52:08.898034Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh normal-auction <ignored manifest> 4 30s docs/benchmarks/p14-20261001T133208Z-31a8c49a-normal`; achieved VUs: 4.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2055 | 10.60 ms | 55.92 ms | 70.46 ms |
| Bid HTTP duration | 316 | 46.22 ms | 66.20 ms | 78.91 ms |
| Maximum HTTP duration | 158 | 45.44 ms | 72.39 ms | 84.77 ms |

Achieved request rate: 68.37/s; iterations: 1581; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 2055 |
| Accepted mutations | 474 |
| Domain rejections | 0 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 767 bid rows, 105 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.02%, memory 118.2MiB / 30.32GiB.
- During: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 8/11; API CPU 63.47%, memory 120.7MiB / 30.32GiB.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 118.4MiB / 30.32GiB.
- Auction lock wait / place_bid: 312 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.
- Bid processing / accepted: 312 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 473 observed histogram samples; p50/p95/p99 **bucket upper bounds** 10.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 473 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 5.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.

At this 4 VU load, all 474 mutation commands were accepted across eight auctions. The place-bid lock-wait p95 bucket upper bound was 5 ms, while HTTP bid p95 was 66.20 ms. The during-run outbox sample showed 8 Sidekiq and 11 Kafka rows pending; both were zero afterward. This is a baseline at one modest load level, not a saturation result.
