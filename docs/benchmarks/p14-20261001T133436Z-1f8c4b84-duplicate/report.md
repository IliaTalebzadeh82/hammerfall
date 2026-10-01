# duplicate — p14-20261001T133436Z-1f8c4b84

Recorded from commit `c86f4f81511d796593a4aea57bb6689ca4f64a65` at 2026-10-01T13:34:42.361584+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 1 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:54:36.028165Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh duplicate-retries <ignored manifest> 8 15s docs/benchmarks/p14-20261001T133436Z-1f8c4b84-duplicate`; achieved VUs: 8.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2507 | 6.62 ms | 13.04 ms | 20.29 ms |
| Bid HTTP duration | 2507 | 6.62 ms | 13.04 ms | 20.29 ms |
| Replay HTTP duration | 2381 | 6.62 ms | 13.09 ms | 20.55 ms |

Achieved request rate: 165.07/s; iterations: 2507; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1 |
| Accepted mutations | 1 |
| Domain rejections | 0 |
| Idempotent replays | 2381 |
| Conflicts | 125 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 1 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.12%, memory 119.7MiB / 30.32GiB.
- During: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 89.80%, memory 123.8MiB / 30.32GiB.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 121.5MiB / 30.32GiB.
- Auction lock wait / place_bid: 1 observed histogram samples; too few for useful percentile reporting.
- Bid processing / accepted: 1 observed histogram samples; too few for useful percentile reporting.
- Bid processing / rejected: 125 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.
- Publisher delivery / Kafka: 3 observed histogram samples; too few for useful percentile reporting.
- Publisher delivery / Sidekiq: 3 observed histogram samples; too few for useful percentile reporting.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.

The single original command was followed by 2,381 matching replays and 125 intentional conflicting-key requests. PostgreSQL retained one completed idempotency outcome, one visible bid, revision 3 and the original deadline; the stored response matched the bid row. Replay p50/p95/p99 were 6.62/13.09/20.55 ms. The original request was a single 37.41 ms sample, so no original-request percentile or strong speed ratio is claimed.
