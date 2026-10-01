# Phase 15 Session 2 — controlled runtime comparisons

2026-10-01. All runs used commit `2b2f94d332bade5b660833cfd6f7c439f3a0c26d`
plus the stated diagnostic-only working-tree edits, the 64-VU/20-second hot
scenario, one auction, 32 bidders, one API Puma process, development Rails,
the same Compose services, and an authoritative PostgreSQL checker after each
run. A separate 5-second one-VU read-only warm-up preceded each measurement.
All retained runs had zero unexpected HTTP outcomes and zero checker failures.
`p14-*` remains the unchanged fixture naming convention. These are shared-host
comparisons, not capacity or SLO measurements.

## Diagnostic ON/OFF control

The first comparison changed only `PERFORMANCE_DIAGNOSTICS`; no CPU profile was
active. The opt-in hooks include the private Puma control socket and DB
checkout instrumentation. `PROFILE_RUNTIME` is separately identified below
because its 0.2-second external polling adds another intervention.

| Diagnostics | Run | HTTP/s | Accepted/s | Rejects | p50/p95/p99 ms | API CPU | API memory | Checker |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| off | [a9035fad](p14-20261001T155954Z-a9035fad-hot/report.md) | 157.69 | 2.45 | 1,590 | 301/700/766 | 115.75% | 114.8 MiB | pass |
| on | [e7bb689c](p14-20261001T160242Z-e7bb689c-hot/report.md) | 127.68 | 1.96 | 1,296 | 466/701/781 | 133.85% | 110.6 MiB | pass |
| off | [03ac5693](p14-20261001T160354Z-03ac5693-hot/report.md) | 155.97 | 2.44 | 1,577 | 305/816/982 | 111.76% | 111.6 MiB | pass |
| on | [51df0d77](p14-20261001T160515Z-51df0d77-hot/report.md) | 159.09 | 2.50 | 1,605 | 321/693/849 | 113.96% | 109.8 MiB | pass |
| on | [81da095a](p14-20261001T160631Z-81da095a-hot/report.md) | 165.53 | 2.64 | 1,666 | 273/626/715 | 124.12% | 109.8 MiB | pass |
| off | [ae94e26d](p14-20261001T160900Z-ae94e26d-hot/report.md) | 168.74 | 2.65 | 1,695 | 299/616/663 | 114.03% | 113.7 MiB | pass |

With hooks enabled, checkout p95 was in the ≤1 ms bucket and no blocking pool
wait was observed. With hooks off, these measurements are unavailable. The
three later ON/OFF results overlap; the initial low ON result did not repeat.
Classification: **within local noise, no stable material hook overhead
established**. Two additional ON runs with external runtime sampling reached
[120.59/s](p14-20261001T160127Z-e3bd2237-hot/report.md) and
[160.95/s](p14-20261001T160734Z-a326a384-hot/report.md); both had a Puma
backlog median of 56–58, checkout p95 ≤1 ms, no pool waits, lock p95 ≤25 ms,
and passing checkers. This spread prevents a precise sampler-overhead claim.

## Development reloading

Rails 8.1 development has `enable_reloading=true` and uses
`ActionDispatch::Reloader` to check watched files on requests. Its configured
file watcher is `ActiveSupport::FileUpdateChecker`; production disables
reloading, but also changes eager loading, SSL, error handling, logging,
hosts and credentials. To isolate the file-check path, this session added
`PERFORMANCE_DISABLE_RELOADING=true` for the **API only** in development.
Rails remained in development with eager loading off and its other settings
intact. The request reloader disappeared when enabled; the development
pending-migration checker remained. All runs below had telemetry and
diagnostics enabled, three Puma threads, DB pool three, and runtime sampling.

| Reloading | Run | HTTP/s | Accepted/s | Rejects | p50/p95/p99 ms | Backlog median | Checkout p95 | Pool waits | Lock p95 | API CPU | Memory | Peak FDs | Checker |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| on | [51104571](p14-20261001T161107Z-51104571-hot/report.md) | 154.62 | 2.41 | 1,583 | 305/677/746 | 57 | ≤1 ms | 0 | ≤10 ms | 116% | 116 MiB | 86 | pass |
| off | [5ad0a5e5](p14-20261001T161227Z-5ad0a5e5-hot/report.md) | 178.95 | 2.80 | 1,795 | 250/614/686 | 57 | ≤1 ms | 0 | ≤25 ms | 107% | 123 MiB | 85 | pass |
| off | [6f9ec0d6](p14-20261001T161334Z-6f9ec0d6-hot/report.md) | 166.19 | 2.67 | 1,716 | 225/891/1016 | 57 | invalid* | 0 | invalid* | 132% | 135 MiB | 85 | pass |
| on | [331b8324](p14-20261001T161448Z-331b8324-hot/report.md) | 146.17 | 2.28 | 1,492 | 366/715/822 | 57 | ≤1 ms | 0 | ≤10 ms | 116% | 117 MiB | 86 | pass |
| on | [1d0c7148](p14-20261001T161556Z-1d0c7148-hot/report.md) | 157.84 | 2.49 | 1,596 | 287/761/916 | 57 | ≤1 ms | 0 | ≤10 ms | 119% | 118 MiB | 86 | pass |
| off | [0e2f6ced](p14-20261001T161707Z-0e2f6ced-hot/report.md) | 171.66 | 2.67 | 1,741 | 279/605/677 | 57 | ≤1 ms | 0 | invalid* | 112% | 119 MiB | 85 | pass |

*Prometheus cumulative histogram deltas were negative across snapshots,
consistent with a counter reset or series replacement, so those percentiles
cannot be used. A report renderer error on the
last run's above-finite-bucket observation was fixed; its k6 output, snapshots,
checker and zero unexpected-error counts were complete before rendering.

Reloading disabled produced 166–179 HTTP/s and 2.67–2.80 accepted/s versus
146–158 HTTP/s and 2.28–2.49 accepted/s with reloading enabled. This is a
repeatable directional service-rate gain in this local window. p95 and p99
ranges overlap; the worst disabled run was slower in the tail. Backlog remained
near 57, so the fraction of admission pressure removed cannot be quantified.
This is a development-runtime artifact, not a production tuning result.

A bounded [CPU profile with reloading disabled](p14-20261001T161926Z-5831cdc3-hot/report.md)
collected 19,743 samples, 2.63% missed. `FileUpdateChecker#updated?` fell
from Session 1's 13.3% inclusive to 2.9%; its remaining caller was
`ActiveRecord::Migration::CheckPending#call`. `PG::Connection#exec` was 4.9%
self, GC 5.57%, and `OpenTelemetry::Trace::Tracer#in_span` 1.2% self (74.5%
inclusive includes application work below it). No single domain method
dominated. Profiling is an extra intervention and its HTTP score is excluded
from the comparison.

## API telemetry

With reloading disabled, three threads and pool three, only the API
`OTEL_ENABLED` setting changed. Other Compose services retained their settings.
The main benchmark's telemetry-required guard was explicitly bypassed for
the telemetry-off diagnostic. `PERFORMANCE_DIAGNOSTICS=true` and external
runtime sampling remained set, but DB diagnostic histograms are unavailable
when OTel is off. Every run passed the checker.

| API OTel | Runs | HTTP/s range | Accepted/s range | p50 range | p95 range | p99 range | Backlog median | API CPU range | API memory range | Peak FDs | Checker |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| on | [5ad0a5e5](p14-20261001T161227Z-5ad0a5e5-hot/report.md), [6f9ec0d6](p14-20261001T161334Z-6f9ec0d6-hot/report.md), [0e2f6ced](p14-20261001T161707Z-0e2f6ced-hot/report.md), [22efc476](p14-20261001T162446Z-22efc476-hot/report.md), [107e098e](p14-20261001T162614Z-107e098e-hot/report.md) | 158.64–178.95 | 2.47–2.80 | 225–373 ms | 577–891 ms | 622–1,016 ms | 56–57 | 107–132% | 117–135 MiB | 85–86 | 5/5 pass |
| off | [45c65364](p14-20261001T162120Z-45c65364-hot/report.md), [3df41072](p14-20261001T162224Z-3df41072-hot/report.md), [ad0ffb58](p14-20261001T162330Z-ad0ffb58-hot/report.md) | 184.49–211.40 | 2.95–3.39 | 208–269 ms | 574–653 ms | 699–738 ms | 55–56 | 110–142% | 121–133 MiB | 83–84 | 3/3 pass |

Disabling API telemetry produced a directional throughput and useful-work
gain beyond these within-window ranges. Tail latency, CPU and memory did not
show a comparably stable gain. **Decision: retain OTel enabled** because
auction, outbox, lock, pool and error visibility are operationally valuable;
disabling it is not an acceptable optimization. The overhead is real enough
to warrant targeted instrumentation-cost work in a later phase or session,
without removing observability now.

## Puma threads and DB pool

The tuning baseline was development with reloading disabled, API OTel and
diagnostics on, one Puma process, three threads, pool three, 1,024 soft FDs.
The first thread experiment set five threads while fixing pool three. After
blocking checkout waits appeared, one bounded pool experiment set pool five
while keeping five threads. Each configuration ran twice and passed the
checker. The last two runs restored three threads and pool three. All used
runtime sampling. The host/service window shifted: restored baseline was
about 113/s versus 146–179/s earlier. Thus cross-window throughput deltas
are not a clean causal estimate.

| Threads/pool | Runs | HTTP/s | Accepted/s | p50/p95/p99 ms | Backlog median | Checkout p95 | Pool waits/p95 | Lock p95 | CPU | Memory | FDs | PG sessions | Checker |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 5/3 | [0d46bd0e](p14-20261001T180641Z-0d46bd0e-hot/report.md) | 95.34 | 1.42 | 629/895/1061 | 56 | ≤25 ms | 2,292/≤50 ms | ≤25 ms | 104% | 116 MiB | 86 | 11 | pass |
| 5/3 | [ee8871ca](p14-20261001T180758Z-ee8871ca-hot/report.md) | 93.48 | 1.40 | 644/943/1056 | 56 | ≤25 ms | 2,298/≤50 ms | ≤25 ms | 104% | 118 MiB | 86 | 11 | pass |
| 5/5 | [d72cfbf5](p14-20261001T180930Z-d72cfbf5-hot/report.md) | 91.35 | 1.32 | 656/929/1060 | 56 | ≤1 ms | 0 | ≤100 ms | 106% | 119 MiB | 87 | 13 | pass |
| 5/5 | [d48d1b1f](p14-20261001T181047Z-d48d1b1f-hot/report.md) | 107.91 | 1.60 | 561/766/837 | 56 | invalid* | 0 | invalid* | 106% | 122 MiB | 87 | 13 | pass |
| 3/3 restored | [d88f454f](p14-20261001T181222Z-d88f454f-hot/report.md) | 112.75 | 1.67 | 521/782/879 | 58 | ≤1 ms | 0 | ≤25 ms | 103% | 118 MiB | 86 | 11 | pass |
| 3/3 restored | [d77de118](p14-20261001T181332Z-d77de118-hot/report.md) | 112.56 | 1.67 | 530/766/980 | 58 | invalid* | 0 | invalid* | 104% | 118 MiB | 86 | 11 | pass |

Pool three with five threads caused repeatable blocking waits absent at three
threads. Pool five removed them but increased DB sessions by two and exposed
greater auction-lock wait in one valid run. It did not produce a repeatable
useful-work or tail improvement; backlog stayed high. **Decision: reject
five-thread tuning and reject a larger DB pool for this workload.** The
experimental configuration overrides were removed from the working tree.
No multi-worker, FD-limit, publisher or auction-lock change is justified.

## Resource and correctness assessment

Peak sampled FDs stayed 83–87 in the 64-VU runs. During-run API memory
snapshots were roughly 110–135 MiB across the controlled windows; the CPU
profile and container restarts prevent a leak inference. CPU snapshots were
roughly one core with occasional higher readings, but the large throughput
shift between windows without a config change cautions against a saturation
or capacity claim. All mutation runs passed the authoritative PostgreSQL
checker, including the run whose Markdown rendering initially failed.

The private Puma control socket remains opt-in. Checkout/pool hooks remain
opt-in through `PERFORMANCE_DIAGNOSTICS` and OTel. StackProf remains disabled
by default and is for bounded local profiles only. The new development
reloading switch defaults to normal reloading and is solely a diagnostic
control. No performance setting was adopted for ordinary runtime operation.
Text artifacts were scanned for private maximums, raw keys, key digests,
priority, origin and credentials; no listed fields were retained after
removing the unnecessary duplicate-key digest from these snapshots and
future capture. Raw run directories hold machine snapshots and profiler
output.

## Adversarial review at checkpoint

The ON/OFF hook control did not establish a repeatable measurement penalty;
external sampling remains a separate intervention. The reloading comparison
isolated the request reloader but retained development migration checks and
cannot stand in for full production mode. Disabling reloading improved useful
work but left backlog high and did not reliably improve p99. The telemetry
switch also disables its opt-in diagnostic metric recording, so that
comparison measures the full API OTel-enabled path rather than a particular
instrumentation library call. Five threads moved delay into DB checkout at
pool three; pool five removed that wait while increasing DB sessions and
auction-lock contention in one valid sample. Neither candidate beat the
restored baseline. Shared-host drift makes a precise causal percentage or
capacity estimate unsound. Correctness checkers passed, and no lock,
deadline, idempotency or publication logic changed. No safety sabotage was
needed because no permanent concurrency change was adopted. Phase 16 work
was not started.
