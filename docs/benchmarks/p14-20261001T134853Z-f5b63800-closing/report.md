# closing — p14-20261001T134853Z-f5b63800

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T13:49:00.250031+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 64 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T13:49:13.797264Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh final-minute <ignored manifest> 16 25s docs/benchmarks/p14-20261001T134853Z-f5b63800-closing`; achieved VUs: 16.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 2312 | 146.62 ms | 202.59 ms | 235.78 ms |
| Bid HTTP duration | 1156 | 160.05 ms | 216.38 ms | 245.30 ms |

Achieved request rate: 91.25/s; iterations: 1156; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1294 |
| Accepted mutations | 138 |
| Domain rejections | 1018 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 138 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Closing: 1 recorded extensions; original end 2026-10-01T13:49:13.797264Z; final end 2026-10-01T13:50:43.797264Z; closed at 2026-10-01T13:50:44.037671Z; close lag 0.240407 s; leader/winner 544/544.
- Extension revisions and observation times are in `verify.json`; closer polling observations are in `closer-observations.json`. Event observation time follows the DB decision and is not itself the decision timestamp.
- PostgreSQL outbox event time preceded the prior effective deadline for 138 mutation events; 0 event time(s) cannot establish eligibility after a queued decision.
- Before: PostgreSQL 9 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.03%, memory 129.3MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- During: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 3/3; API CPU 102.71%, memory 128.3MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- After: PostgreSQL 11 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.08%, memory 128.3MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0, 'hammerfall.audit.v1': 2.0}; gauges are asynchronous and can be stale.
- Auction lock wait / place_bid: 1156 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 25.00 ms, 50.00 ms.
- Bid processing / accepted: 138 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Bid processing / rejected: 1018 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 100.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 139 observed histogram samples; p50/p95/p99 **bucket upper bounds** 25.00 ms, 25.00 ms, 25.00 ms.
- Publisher delivery / Sidekiq: 139 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 10.00 ms, 10.00 ms.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
