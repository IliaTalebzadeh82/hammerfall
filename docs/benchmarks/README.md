# Phase 14 benchmark evidence

These are local Compose runs on a shared Intel Core Ultra 7 155H host with
30.3 GiB RAM, Docker 29.8.1 and k6 1.8.1. They are measurements of this
environment, not production capacity or SLOs. Each retained `p14-*` directory
contains `report.md`, exact commands, k6 summary/log, environment and telemetry
snapshots, and PostgreSQL verification. The active [ExecPlan](../plans/phase-14-execplan.md)
has the current Evidence Index and unresolved work.

## Session 2 experiments and interpretation

The [Session 2 analysis](phase-14-session-2.md) contains the saturation and
scenario comparison tables, 1,000-bidder failure reconciliation, fanout
steps, resource/telemetry correlation, recovery read, checker sabotage and
evidence-classified Phase 15 questions. Its retained runs cover closing,
controlled one-row/eight-row work, hot 8/16/32/64 VUs, 400/600/1,000
final-ten-second bursts, 50/200/500 Action Cable subscribers, a targeted
duplicate burst and normal/hot repeats. The highest clean local final-ten
burst observed was 600 contenders; the 1,000 attempt hit the API container's
1,024-open-file soft limit and had 28 server errors plus 64 timeouts. All
post-run PostgreSQL state checkers passed; this does not turn the degraded
HTTP run into a capacity success.
The [final evidence review](phase-14-final.md) summarizes methodology limits,
Phase 15 investigation inputs and the local regression/runtime/browser gates.

During Session 2, `git rev-parse HEAD` recorded application commit `fec1826`
in snapshots while the expanded harness was being developed in the working
tree. The final harness was committed as `4f7932e`. Scenario scripts for the
primary step series were stable after their first validation; capture/report
fields changed as noted in the analysis. The failed first fanout handshake
run and the closing postprocessing repair remain labeled with their raw
evidence. Do not treat these measurements as having been taken from a clean
`4f7932e` checkout. API observability and Compose service settings stayed
unchanged throughout the primary comparisons.

## Primary committed-harness runs

All three used harness commit `c86f4f8`, API OTEL enabled, a separate 1 VU
read-only five-second warm-up, fresh fixtures and no configured container CPU or
memory limits. Durations are 30 seconds for normal/hot and 15 seconds for
duplicate. p50/p95/p99 below are k6 **HTTP request** milliseconds; operation
latencies and histogram bucket bounds are in the individual reports.

| Scenario | VUs | HTTP requests / achieved rate | p50 / p95 / p99 ms | Mutation outcomes | Unexpected errors | PostgreSQL check |
|---|---:|---:|---:|---|---:|---|
| [Normal, 8 auctions](p14-20261001T133208Z-31a8c49a-normal/report.md) | 4 | 2,055 / 68.37/s | 10.60 / 55.92 / 70.46 | 474 accepted; 0 domain rejected | 0 | Passed |
| [One hot auction](p14-20261001T133320Z-03f35c6c-hot/report.md) | 8 | 3,038 / 100.83/s | 52.23 / 88.94 / 107.64 | 370 accepted; 1,149 domain rejected | 0 | Passed |
| [Duplicate retries](p14-20261001T133436Z-1f8c4b84-duplicate/report.md) | 8 | 2,507 / 165.07/s | 6.62 / 13.04 / 20.29 | 1 original; 2,381 replay; 125 intentional conflict | 0 | Passed; 1 logical bid |

The normal and hot rows have different workload mixes and VU counts, so their
HTTP rates are not a controlled throughput comparison. In the hot run, bid
HTTP p95 was 96.42 ms and the lock-wait p95 fell in the ≤50 ms histogram bucket;
post-lock work and other overhead remain to be isolated. One during-run sample
saw 4 Sidekiq and 7 Kafka outbox rows pending, which drained afterward. This
does not establish a queue saturation threshold. The duplicate outcome check
found one stored command, one bid and no repeated deadline extension.

## Exploratory and harness-validation runs

- [Normal telemetry off](p14-20261001T132051Z-129892c8-normal/report.md) and
  [normal telemetry on](p14-20261001T132222Z-5726b97d-normal/report.md) used
  an uncommitted harness. They are retained for setup history and possible
  variability context, not a reliable telemetry-overhead estimate.
- [Hot initial](p14-20261001T132341Z-d1dba139-hot/report.md) and
  [hot settled](p14-20261001T132634Z-e4799928-hot/report.md) used an
  uncommitted harness. The initial hot metric snapshot was incomplete because
  export/scrape had not settled. The later run captured all bid lock samples.
- [Duplicate exploratory](p14-20261001T132438Z-af7f5e0e-duplicate/report.md)
  used the earlier checker.
- `validation-*` folders contain short harness smoke output. The first normal
  smoke exposed a correlation between workload slot and auction selection;
  the selection was fixed and validated across all eight auctions before the
  primary runs. These are not benchmark comparisons.

Final gate logs are indexed in
[phase-14-final-gates](phase-14-final-gates/README.md). Hosted CI evidence is
recorded in the Phase 14 ExecPlan when available.
