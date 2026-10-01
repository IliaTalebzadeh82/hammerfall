# fanout — p14-20261001T135326Z-6393b2c3

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T13:53:33.848962+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 24 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:13:26.456901Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh websocket-fanout <ignored manifest> 10 15s docs/benchmarks/p14-20261001T135326Z-6393b2c3-fanout`; achieved VUs: 11.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 38 | 19.61 ms | 38.31 ms | 40.25 ms |
| Bid HTTP duration | see outcome counts | 36.15 ms | 38.66 ms | 40.82 ms |

Achieved request rate: 1.35/s; iterations: 39; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 38 |
| Accepted mutations | 19 |
| Domain rejections | 0 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 19 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.

## Action Cable client observations

These receipts are k6 client observations of invalidation hints, not proof of universal browser delivery or authoritative state.

- Attempted sockets: 20.
- Opened sockets: 20.
- Confirmed subscriptions: 20.
- Failed sockets: 0.
- Invalidations received: 190.
- Disconnected sockets: 20.
- Before: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.17%, memory 149.5MiB / 30.32GiB.
- During: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 1/2; API CPU 7.12%, memory 152.4MiB / 30.32GiB.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.16%, memory 151.3MiB / 30.32GiB.
- Auction lock wait / place_bid: 19 observed histogram samples; too few for useful percentile reporting.
- Bid processing / accepted: 19 observed histogram samples; too few for useful percentile reporting.
- Publisher delivery / Kafka: 21 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 21 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
