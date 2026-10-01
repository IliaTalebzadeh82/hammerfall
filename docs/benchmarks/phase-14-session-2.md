# Phase 14 Session 2 — local load evidence

2026-10-01. These are measurements of one shared local Compose host, not a
production capacity estimate or SLO. The application HEAD during the runs was
`fec1826`; the extended harness was developed in the working tree and then
committed as `4f7932e`. The hot load script itself was unchanged from
`c86f4f8`. Capture/report fields evolved during the campaign; the run folders
preserve their actual snapshots and commands. The first fanout and closing
postprocessing repairs are labeled below. Do not describe the measured harness
as clean at run time merely because its final version is committed now.

The main runs used k6 1.8.1, API `OTEL_ENABLED=true`, one Rails/Puma process
with 3 threads and a 3-connection DB pool, Sidekiq concurrency 2, no Compose
CPU/memory caps, and a separate 1-VU/5-second read-only warm-up. The API's
open-file soft limit was 1,024. Fixtures were unique and no auction business
logic or permanent runtime setting was changed. `run.sh` used a 15-second
request timeout and 0.05-second hot/closing think delay unless the scenario
script specifies its own pacing. See each linked `before.json`, `commands.txt`,
`summary.json`, `k6.log.gz`, and `verify.json` for exact conditions and raw
evidence. Closed-loop VUs are offered concurrency, not a fixed arrival rate.

## Hot-auction saturation

Each row uses one auction and the same read-then-bid loop. p50/p95/p99 are k6
**all-HTTP** latency in milliseconds. Lock p95 is the upper edge of an OTel
histogram bucket, not an exact percentile. The during-run backlog is a single
fixture-scoped Sidekiq/Kafka pending-row sample, not a peak. All five checker
results passed and all unexpected-error counts were zero.

| Run | VUs; seconds | HTTP/s | accepted/s | expected rejects | p50 / p95 / p99 ms | lock p95 ≤ ms | pending S/K |
|---|---:|---:|---:|---:|---:|---:|---:|
| [Hot baseline](p14-20261001T133320Z-03f35c6c-hot/report.md) | 8; 30 | 100.83 | 12.28 | 1,149 | 52.23 / 88.94 / 107.64 | 50 | 4/7 |
| [Hot repeat](p14-20261001T141357Z-145202b0-hot/report.md) | 8; 30 | 84.26 | 9.85 | 973 | 68.80 / 106.18 / 121.41 | 50 | 7/8 |
| [Hot step](p14-20261001T135755Z-2d0a8357-hot/report.md) | 16; 20 | 91.40 | 5.47 | 816 | 146.39 / 198.39 / 225.09 | 50 | 4/5 |
| [Hot step](p14-20261001T135902Z-8aa52575-hot/report.md) | 32; 20 | 98.55 | 2.98 | 948 | 294.84 / 392.24 / 436.86 | 25 | 1/3 |
| [Hot step](p14-20261001T140007Z-fc33291e-hot/report.md) | 64; 20 | 95.44 | 1.42 | 976 | 630.01 / 934.81 / 1,036.64 | 25 | 1/1 |

HTTP throughput flattened around the 8–16 VU region while latency continued
to rise through 64 VUs. The two 8-VU runs themselves differ by about 16% in
HTTP rate and 17 ms in p95; host load and API resident memory also changed
after earlier experiments. Thus this is a broad **local degradation region**,
not a precise knee or maximum capacity. More contenders read an already stale
price, so accepted-bid throughput falls as expected rejections rise. No k6
iterations were dropped in these closed-loop runs.

At 64 VUs, bid HTTP p95 was 956 ms; auction lock-wait p95 was in the ≤25 ms
bucket and rejected-bid processing p95 in the ≤100 ms bucket. The API sample
used 105% CPU, k6 used 14%, host load was about 2.5 on 22 logical CPUs, and
PostgreSQL showed no lock waiter in that one sample. A 32-VU sample did catch
one PostgreSQL `Lock:transactionid` waiter. **H1 (row-lock wait dominates
tail)** is unsupported in this configuration: most observed HTTP tail is
outside the auction lock and instrumented bid-processing span. Request
queueing before that span and Ruby/Puma work are plausible, but lack direct
queue/CPU profiling. **H2 (pool wait amplifies row wait)** remains unresolved:
pool size is 3, but checkout wait was not instrumented, and sparse DB samples
cannot prove it absent. Do not interpret the 12 total PostgreSQL sessions as
12 API pool connections; other Compose roles also connect.

The same loop at 16 VUs across [eight independent auction rows](p14-20261001T140112Z-770c0b73-distributed/report.md)
accepted 590 bids (29.03/s) versus 111 (5.47/s) on one row; lock p95 moved
from ≤50 to ≤10 ms. HTTP throughput was **lower** (78.74 versus 91.40/s) and
p95 **higher** (239.86 versus 198.39 ms), because the eight-row run performed
many more expensive accepted mutations and publications. Partitioning improved
useful accepted work in this local comparison; it did not demonstrate a
general HTTP capacity increase. The original [normal-load run](p14-20261001T133208Z-31a8c49a-normal/report.md)
and its [repeat](p14-20261001T141516Z-7637fb67-normal/report.md) delivered
68.37/63.85 HTTP/s with p95 55.92/68.53 ms and 474/443 accepted mutations.
Their mixed 50% auction-read, 20% history-read, 20% bid, 10% maximum-bid
workload differs from the hot loop, so their HTTP rates are not a controlled
row-partitioning comparison. Both repeat runs passed DB verification.

## Closing storm and final-ten-second challenge

The [16-VU closing storm](p14-20261001T134853Z-f5b63800-closing/report.md)
sent 2,312 HTTP requests over 25 seconds: 138 accepted bids, 1,018 expected
domain rejections and no unexpected HTTP failures. HTTP p50/p95/p99 was
146.62/202.59/235.78 ms; lock p95 ≤25 ms. Revision 3 extended the original
13:49:13.797264 UTC deadline exactly 90 seconds to 13:50:43.797264. The
independent closer finalized at 13:50:44.037671 (0.240 s lag), with leader
and winner both user 544. PostgreSQL outbox event time for each accepted
mutation preceded its prior effective deadline. The checker found contiguous
history, coherent price/leader/revisions, the final close event and no invalid
state. The [postprocessing repair](p14-20261001T134853Z-f5b63800-closing/diagnostics.md)
preserves a harness-shell interruption and arithmetic correction; measured k6
traffic was unaffected.

The burst script launched one distinct bidder per k6 VU at a client-paced
target eight seconds before the **original** deadline. Client time did not
decide legality. In all three runs, actual attempted requests equaled VUs,
each VU completed its one iteration, and launch-offset p99 was 69, 67 and
72 ms respectively. These observations support a concentrated generator
launch, though they do not prove all requests were simultaneously executing
inside Rails.

| Run | attempts | accepted / expected rejected | server errors / timeouts | HTTP p50 / p95 / p99 | DB command records | result |
|---|---:|---:|---:|---:|---:|---|
| [400 bidders](p14-20261001T140644Z-77e49a45-challenge/report.md) | 400 | 1 / 399 | 0 / 0 | 3.08 / 5.98 / 6.24 s | 400 | Checker passed; closed after one valid extension |
| [600 bidders](p14-20261001T140944Z-9e4ab8a6-challenge/report.md) | 600 | 1 / 599 | 0 / 0 | 4.70 / 8.81 / 9.20 s | 600 | Checker passed; closed after one valid extension |
| [1,000 attempt](p14-20261001T140304Z-02bb53d7-challenge/report.md) | 1,000 | 1 / 907 | 28 / 64 | 7.46 / 15.00 / 15.00 s | 911 | Checker passed; HTTP campaign degraded |

At 400/600, in-burst API CPU was 93/102%, k6 CPU 4/5%, and k6 memory
154/230 MiB. PostgreSQL lock p95 was ≤25 ms in both; sparse in-burst samples
found no lock waiter. The 600 run is the **highest clean burst observed here**,
not a capacity claim. The 1,000 attempt produced 28 API `Errno::EMFILE`
exceptions against the 1,024-open-file soft limit and 64 HTTP timeouts. Its
diagnostic sample missed the peak. [Detailed failure reconciliation](p14-20261001T140304Z-02bb53d7-challenge/diagnostics.md)
records 911 completed idempotency outcomes versus 908 successful/expected
HTTP responses; at least three failed HTTP observations had a committed DB
outcome. No duplicate authoritative mutation or wrong winner was observed.
The environment file-descriptor limit, not PostgreSQL capacity, limits what
can be concluded from the 1,000 attempt. No limit was raised for scoring.

## Action Cable fanout and replay

The valid one-connection-per-VU [50](p14-20261001T135446Z-84129c80-fanout/report.md),
[200](p14-20261001T135552Z-bf4c36d0-fanout/report.md), and
[500](p14-20261001T141249Z-2541f463-fanout/report.md) subscriber steps
confirmed every subscription, with zero socket failures. They received
1,400/5,600/13,500 invalidation hints for 28/28/27 accepted bids. Connection
establishment p95 grew from 234 to 784 to about 2,000 ms; API HTTP p95 on
56/56/54 low-rate mutation/read requests was 45/40/137 ms. The 500-socket
in-run sample had 522 API open files, 15% API CPU, 6% k6 CPU, Redis below 1%
and Sidekiq below 1%; all fixture outbox rows drained afterward. This shows
growing handshake time and some API latency effect, with small HTTP samples;
the global server-broadcast counter rose by 30 and the 30-sample global
broadcast-lag histogram had p50/p95 bucket bounds ≤1/2.5 seconds. Those
signals are not fixture-scoped and cannot establish a per-client delivery
latency distribution. The run does not establish a backpressure loss
threshold. Larger fanout remains
unresolved under the known 1,024-file container limit. k6 receipts mean its
clients received **server invalidations**; they do not establish universal
browser delivery, durable delivery or authoritative state. The first
[fanout attempt](p14-20261001T135149Z-8e3b091d-fanout/report.md) omitted an
allowed `Origin` and all handshakes were correctly rejected; it is a harness
validation failure. A later 10-VU run used looping subscribers, so it is not
part of the controlled one-connection-per-VU series.

The original [duplicate run](p14-20261001T133436Z-1f8c4b84-duplicate/report.md)
produced one bid, 2,381 completed replays and 125 intentional conflicts.
Replay p95 was 13.09 ms; the one original request was 37.41 ms, insufficient
for an original latency percentile. The targeted [64-VU duplicate burst](p14-20261001T141653Z-988dbc9b-burst/report.md)
produced one original and 127 replays. Simultaneous first-wave p95 was
347 ms; a second replay wave 0.5 seconds later had p95 52 ms. The lock-wait
histogram recorded one auction-lock sample, consistent with replay bypassing
the mutation block. **H6 is supported qualitatively**: completed replay is
cheaper than the concurrent first wave. The first wave includes Puma/request
queueing and idempotency-record ownership wait; this run cannot separate them.

## Publisher, recovery and Phase 15 evidence classes

The eight-row run's one during snapshot found 17 Sidekiq and 13 Kafka fixture
outbox rows pending; both were zero in the after snapshot. Publisher-delivery
p95 bucket bounds were ≤5 ms for Sidekiq and ≤25 ms for Kafka over 606 samples
each. Hot and closing runs also drained their smaller sampled backlogs after
load. [Recovery read](recovery-check.json) found nine selected auctions' Redis
public revisions equal PostgreSQL, zero pending fixture outbox rows and empty
Sidekiq maintenance/notification queues. Kafka lag gauges hovered near one
or a few messages and can be stale while idle; do not claim exact zero lag.
API RSS rose from about 130 MiB before the burst campaigns to about 200 MiB
and remained around 200–205 MiB across later runs; it did not return to the
earlier baseline or show continued growth in this short observation. None of
these snapshots guarantees a recovery time.

| Evidence class | Phase 15 investigation input |
|---|---|
| **Measured local limit** | API 1,024-file soft limit caused 28 `EMFILE` errors in the 1,000 request burst. Reproduce only in an isolated diagnostic environment; it is not a PostgreSQL capacity number. |
| **Likely contributor; needs profiling** | Rails/Puma request queueing and CPU work: HTTP tail rises far more than bid-processing/lock histograms while API uses about one core and k6/host remain below saturation. Instrument admission/queue/checkout boundaries before choosing a change. |
| **Observed auction serialization effect** | One row accepted far fewer bids than eight rows with the same loop, but lock wait was not the dominant observed HTTP tail. Examine useful throughput and rejection mix separately from RPS. |
| **Possible contributor; not material at observed load** | Publisher transaction-held external waits: sampled backlog drained and publisher-duration buckets remained bounded. No measured publisher saturation. |
| **Possible fanout contributor; needs profiling** | Cable handshake p95 reached about 2 seconds at 500 sockets and the global server-broadcast-lag p95 bucket was ≤2.5 seconds, with all subscriptions and invalidations observed by k6. The next limit under current file descriptors is unknown. |
| **Unresolved** | DB pool checkout wait (configured pool 3), precise Puma admission wait, PostgreSQL query/proxy-resolution cost, telemetry overhead and fanout beyond 500. No direct data justifies a pool/index/concurrency change yet. |
| **Not material in these samples** | Kafka, Redis, Sidekiq, host memory/CPU and k6 generator resource use did not show a sustained bottleneck at the clean steps. Sparse snapshots cannot rule out short peaks. |

Adversarial limitations: histogram values are bucket bounds; a single DB and
Docker sample can miss peaks; the 1,000-run sample did; socket API p99 has
only 54–56 HTTP observations per step; one accepted bid in each fixed-amount
challenge says little about accepted-throughput capacity; normal and hot
workload mixes differ; and each hot level has one run except 8 VUs. The
checker verifies snapshots and PostgreSQL state, but cannot reconstruct the
exact private DB decision time for every historical command if an outbox
observation arrives after a deadline. No permanent optimization was made.
[Checker sabotage](validation-checker-sabotage.md) and
[classifier sabotage](validation-classifier-sabotage/README.md) passed with
restoration verified. A controlled telemetry-on/off comparison was not run;
the earlier exploratory pair used a changing harness and is not evidence of
instrumentation overhead.
