# challenge — p14-20261001T140644Z-77e49a45

Recorded from commit `fec182614d0ce21a6ffd60d3b8728fa5c0808285` at 2026-10-01T14:06:54.997984+00:00 UTC.

## Environment and method

- Host: Linux-7.0.0-34-generic-x86_64-with-glibc2.43; Intel(R) Core(TM) Ultra 7 155H; 22 logical CPUs; 30.3 GiB RAM.
- Docker 29.8.1; k6 v1.8.1 (commit/73b044f9f9, go1.26.4, linux/amd64); Compose containers have the recorded resource limits in `before.json` (zero means unset).
- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: 100, 128MB, 4MB, 0, 0; API Puma threads and DB pool: 3; Sidekiq concurrency: 2.
- Kafka topic: 3 partitions; Redis settings: ['appendonly', 'yes', 'maxmemory', '0']; API OTEL_ENABLED=true.
- Fixture: 1 auction(s), 400 bidder(s), starting price 10000 cents, increment 100 cents, ends at 2026-10-01T14:07:27.777177Z.
- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.
- Measurement command: `load-tests/run.sh final-ten <ignored manifest> 400 75s docs/benchmarks/p14-20261001T140644Z-77e49a45-challenge`; achieved VUs: 400.

## Results

| Measure | Count/rate | p50 | p95 | p99 |
|---|---:|---:|---:|---:|
| All HTTP requests | 400 | 3088.49 ms | 5981.93 ms | 6241.52 ms |
| Bid HTTP duration | 400 | 3088.49 ms | 5981.93 ms | 6241.52 ms |

Achieved request rate: 16.30/s; iterations: 400; unexpected HTTP failures: 0.

| Classified outcome | Count |
|---|---:|
| Accepted HTTP (including reads) | 1 |
| Accepted mutations | 1 |
| Domain rejections | 399 |
| Idempotent replays | 0 |
| Conflicts | 0 |
| Client errors | 0 |
| Server errors | 0 |
| Timeouts | 0 |
| Transport errors | 0 |

## Database and telemetry

Authoritative checker: 0 failure(s), 1 bid rows, 0 maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts.
- Closing: 1 recorded extensions; original end 2026-10-01T14:07:27.777177Z; final end 2026-10-01T14:08:57.777177Z; closed at 2026-10-01T14:08:58.044785Z; close lag 0.267608 s; leader/winner 2120/2120.
- Extension revisions and observation times are in `verify.json`; closer polling observations are in `closer-observations.json`. Event observation time follows the DB decision and is not itself the decision timestamp.
- PostgreSQL outbox event time preceded the prior effective deadline for 1 mutation events; 0 event time(s) cannot establish eligibility after a queued decision.
- Before: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.02%, memory 199.8MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.audit.v1': 3.0, 'hammerfall.projection.v1': 2.0}; gauges are asynchronous and can be stale.
- During: PostgreSQL 12 sessions, 2 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 93.27%, memory 203.3MiB / 30.32GiB; k6 CPU 4.30%, memory 153.7MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 2.0}; gauges are asynchronous and can be stale.
- After: PostgreSQL 12 sessions, 1 active, 0 lock waiters; fixture Sidekiq/Kafka pending 0/0; API CPU 0.04%, memory 199.6MiB / 30.32GiB.
  Prometheus snapshot: global outbox pending {'kafka': 0.0, 'sidekiq': 0.0}, oldest age seconds {'kafka': 0.0, 'sidekiq': 0.0}, summed Kafka lag {'hammerfall.projection.v1': 1.0}; gauges are asynchronous and can be stale.
- Auction lock wait / place_bid: 400 observed histogram samples; p50/p95/p99 **bucket upper bounds** 5.00 ms, 25.00 ms, 25.00 ms.
- Bid processing / accepted: 1 observed histogram samples; too few for useful percentile reporting.
- Bid processing / rejected: 399 observed histogram samples; p50/p95/p99 **bucket upper bounds** 50.00 ms, 50.00 ms, 100.00 ms.
- Publisher delivery / Kafka: 4 observed histogram samples; too few for useful percentile reporting.
- Publisher delivery / Sidekiq: 4 observed histogram samples; too few for useful percentile reporting.

## Interpretation and limits

This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.
