# Phase 14 final evidence review

2026-10-01. This is a short local Compose campaign on one shared host. It is
comparative engineering evidence, not a production capacity estimate or SLO.
The [Session 2 analysis](phase-14-session-2.md) and linked per-run folders hold
the exact commands, configuration, raw k6 output, telemetry and PostgreSQL
checks. All 24 retained `p14-*` reports have a command, summary, before
snapshot, compressed k6 log and verifier result; all verifier `failures` arrays
are empty. Exploratory and invalid harness runs remain labeled in the
[index](README.md).

## Findings

- One-row hot load flattened near 84–101 HTTP requests/s at 8–64 closed-loop
  VUs while p95 rose from 89–106 to 935 ms. The two 8-VU runs varied by about
  16% in request rate. At 64 VUs the auction-lock p95 histogram bucket was
  ≤25 ms, so measured lock wait did not explain the HTTP tail. Puma admission,
  DB checkout and Ruby CPU work need finer measurement before any tuning.
- At the same 16-VU loop, eight rows accepted 590 bids versus 111 on one row
  over 20 seconds. The accepted/rejection mix changed; HTTP throughput was
  lower for the eight-row case. This supports an auction serialization effect
  on useful accepted work, not a general RPS claim.
- A closing storm produced one valid 90-second extension and a correct final
  winner. The 400 and 600 contender final-ten bursts completed without
  unexpected HTTP errors. The 1,000 attempt launched every VU but reached the
  API process's 1,024-open-file soft limit: 28 server errors, 64 timeouts and
  at least three HTTP observations with committed DB outcomes. The checker
  found valid auction state. The highest clean local burst observed was 600.
- At 50/200/500 Cable subscribers, all subscriptions were confirmed and k6
  received 1,400/5,600/13,500 invalidation hints. Receipts establish neither
  durable delivery nor universal browser freshness. The 500-socket step had
  about 2-second handshake p95; larger fanout under the current file limit
  remains unresolved.
- Completed idempotent replay was cheaper than the concurrent first wave in a
  targeted burst, consistent with bypassing auction mutation. The first wave
  combines ownership and admission waits, so the exact saving is unresolved.
- Sampled outbox backlog drained, nine selected Redis projections agreed with
  PostgreSQL after load, and selected Sidekiq queues were empty. No measured
  publisher, Kafka, Redis, Sidekiq, host or k6 generator saturation was found
  at the clean steps. Sparse samples can miss peaks. No controlled stable
  telemetry-on/off comparison was performed.

## Final local gates

Raw logs are in [phase-14-final-gates](phase-14-final-gates/README.md). The
first `scripts/check` run had 11 Redis projection/reconciliation failures among
439 examples because live development and test projection keys shared Redis
DB 0 and auction IDs overlapped. Repeating the 24 affected examples with Redis
DB 15 passed (2 expected pending). `scripts/check` now isolates its test Redis
endpoint; the complete rerun passed 439 examples, 0 failures, 4 pending, plus
frontend lint/format/types, 73 Vitest tests and production build. RuboCop,
Brakeman, Zeitwerk and bundler-audit passed. Compose config, service health,
scheduled job, Kafka, sequential API, concurrent bid, proxy bid and pruning
smokes passed. Seven real Chrome scenarios against Compose passed, including
lost-response retry, cross-client REST/Cable recovery, soft close and closer.

## Adversarial limits and Phase 15 input

The checker sabotage and HTTP classifier sabotage both detected controlled
invalid input and were restored. The 1,000 HTTP failure is retained and its
ambiguous responses were reconciled against PostgreSQL. k6's burst launch
does not prove all requests were executing simultaneously inside Rails.
Histogram p95 values are bucket upper bounds; a single during-run sample can
miss a peak. The 500-socket API p99 has only 54 observations. The original
normal workload and hot workload have different request mixes. A single local
host, short duration and shared Docker resources prevent extrapolation to
production. No auction business rule, permanent pool/concurrency setting or
publisher design was changed.

The measured local file-descriptor failure and likely Puma/admission work are
the strongest next investigations. Row partitioning changed accepted work,
but auction lock wait did not dominate the measured tail. DB checkout, exact
admission delay, proxy/query cost, telemetry overhead and larger Cable fanout
remain unresolved. Publisher transaction-held network waits are a possible
contributor without a measured sustained bottleneck here. See the
[evidence-class table](phase-14-session-2.md#publisher-recovery-and-phase-15-evidence-classes)
before selecting an optimization. Phase 15 has not begun.

## Final adversarial review

| Area | Check and conclusion | Remaining limit |
|---|---|---|
| Auction correctness and concurrency | Closing, burst, duplicate and hot fixtures passed PostgreSQL sequence, price, leader, deadline, winner and command-effect checks. Controlled checker corruption was detected and restored. | The checker cannot reconstruct every private historical DB decision timestamp from an outbox observation. |
| Failure recovery | The 1,000-bidder HTTP errors were preserved and reconciled with committed command records. Fixture outbox/Sidekiq backlog drained and nine sampled projections matched PostgreSQL after load. | Sparse recovery samples do not prove a guaranteed drain time or absence of short spikes. |
| Privacy and security | The saved benchmark files and compressed logs were scanned for `PGPASSWORD`, `SECRET_KEY_BASE`, `Idempotency-Key`, `key_digest`, `request_fingerprint`, `maximum_amount`, `priority_sequence` and `bid_origin`; none appeared. Brakeman and bundler-audit passed. | The demo API remains unauthenticated; these checks do not qualify public exposure. |
| Generator and metrics | The 1,000 burst launched all VUs, yet server open files limited completion. k6 was not observed CPU-bound in the clean steps. Expected rejections, replays, conflicts, errors and timeouts were separately classified. | Closed-loop VUs are not an arrival rate; histogram buckets, limited p99 samples and shared-host noise limit precision. |
| Tests and documentation | The first broad regression failure was diagnosed and the full local gate rerun passed with test Redis isolation. Reports, raw outputs, verifier results and limitations are linked from the benchmark index. [Hosted CI](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36881034875) passed API, web and Compose on `752fe85`. | The final closure commit changes documentation only. |
