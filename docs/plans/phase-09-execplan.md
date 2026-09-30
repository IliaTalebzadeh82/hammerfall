# Phase 9 ExecPlan — transactional outbox

Status: COMPLETE — verified 2026-09-30. Phase 10 has not begun.
Current milestone: Phase boundary; await an explicit Phase 10 request.
Completed: Atomic public outbox, independent `SKIP LOCKED` publisher, retry metrics,
two-second Redis client network timeout, focused integration, live crash/outage
experiments, sabotage A–D, adversarial review and full local checks.
Verified: See Evidence Index below. No Kafka or Phase 10 implementation started.
Remaining: None within Phase 9. No hosted CI or production capacity claim.
Known limits: Acknowledgment is Sidekiq enqueue only; later Redis loss, job
Dead-set exhaustion or Cable loss can still lose a hint. No exactly-once, global
ordering, fixed delivery deadline or throughput claim. Poisoned rows retry
indefinitely and need operator attention.
Relevant files: `apps/api/app/models/{auction,outbox_event}.rb`,
`app/services/outbox_publisher.rb`, `app/jobs/auction_changed_job.rb`,
`config/initializers/sidekiq.rb`, `bin/outbox_publisher`, outbox migration/spec,
Compose and [ADR-010](../adr/010-transactional-public-outbox.md).
Next-session starting point: Phase 9 is complete. Read latest handoff and the
Phase 10 specification only after an explicit request.

## Decision record

- `auction.changed.v1` is one public-only outbox event per public revision,
  versioned independently of Sidekiq. Initial creation has revision zero/no hint.
- The mutation, revision, outbox row and enclosing idempotency outcome share
  PostgreSQL commit. Publisher claims one due row per transaction with
  `FOR UPDATE SKIP LOCKED`, enqueues, then acknowledges. Retry delay is
  exponential, capped at 300 seconds, with no silent drop.
- Multiple publishers may reorder revisions. The job reads current PostgreSQL
  revision and broadcasts a harmless public hint. No global lock or Kafka scope.
- The publisher logs backlog, due, retry and oldest pending age each cycle.
  `occurred_at` is database transaction time and can predate actual commit.
  Retry, acknowledgment and backlog age use PostgreSQL clock time so publisher
  host skew cannot defer a row beyond the intended retry interval.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Initial atomicity/replay/publisher specs | Focused PostgreSQL suite at primary checkpoint | 22 examples, 0 failures; seed 52519 | Primary implementation commit `5a032e6` |
| Additional publisher concurrency and clock | `bundle exec rspec spec/integration/transactional_outbox_spec.rb` | 9 examples, 0 failures; seed 31458 | Two PostgreSQL connections advance separate rows while one lock is held; one-year host clock skew leaves retry/ack/age on DB time |
| Process crash after commit | Rails runner writes auction 163, bid/revision 3 and three outbox rows, prints IDs, then kills itself with SIGKILL (exit 137); separate runner/publisher/worker | Three rows visible pending after origin death; publisher enqueued all; Sidekiq completed three jobs | Event UUIDs `8a4c91bd…`, `4bed4e57…`, `8ce4966c…`; live terminal observations below |
| Redis outage/recovery and backlog | Stop Compose Redis; verify PostgreSQL `pg_isready`; kill originating runner after auction 164 bid; run publisher once; restart Redis; rerun publisher | Bid price 10,000/revision 3 committed with three pending rows; failure recorded `RedisClient::CannotConnectError`, attempts 1, backlog 3/retries 3; recovery published 3, backlog 0, attempts 2; worker queue drained | Event UUIDs `ec9ed8d0…`, `8ca6d461…`, `34901eae…`; live terminal observations below |
| Crash after enqueue before ack; duplicate | New auction 164 revision 4 event; separate publisher process prepended a kill just before `published_at` update; retry publisher | First publisher exit 137; event `b041fa99…` stayed pending/attempts 0; retry acknowledged it; distinct Sidekiq JIDs `56c1a588…` and `4da5f5f4…` completed; auction revision remained 4 | Live worker logs, 2026-09-30 12:51 UTC |
| Rollback/privacy/no-op/replay | Transactional outbox and public revision specs | Atomic rollback, insert failure, private maximum, identical max, rejection, duplicate close and replay checked | Initial focused 22 examples; expanded test above |
| Sabotage A: omit atomic insert | Temporarily remove `OutboxEvent.record_auction_change!`, run outbox spec, restore byte-identical file | Expected failure: 8 examples, 7 failures; committed event count expected 1/got 0, rollback intent assertion also failed | `/tmp/phase9_sabotage_a.log` (local); source restored |
| Sabotage B: enqueue failure | Stop real Redis while PostgreSQL remains healthy; publisher once | Expected failure persisted as pending/retryable; no command rollback | Redis outage row above |
| Sabotage C: duplicate publication | Kill real publisher after successful enqueue/before acknowledgment, then retry | Two completed jobs, one outbox event, unchanged domain revision | Crash-after-enqueue row above |
| Sabotage D: replay creates event | Temporarily insert an extra event in idempotency replay branch; run one-event spec; restore byte-identical file | Expected failure: event count expected 3/got 4 | `/tmp/phase9_sabotage_d.log` (local); source restored |
| Local full regression | `scripts/check` after clock and timeout fixes | 368 RSpec examples, 0 failures; RuboCop 90 files/0 offenses; Brakeman 0 warnings; Zeitwerk, frontend lint/format/types, 73 Vitest tests and Next build passed | `/tmp/phase9-check-final.log` (local); final focused clock spec and web lint/format rerun after final edits |
| Compose startup | `docker compose up --build --wait --wait-timeout 240` | Eight services healthy, including independent publisher | `/tmp/phase9-compose.log` (local) |
| Browser/HTTP/security | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e`; Compose concurrent/proxy/sequential smoke; two-process idempotency smoke; `bin/bundler-audit` | 7/7 browser; all four API smokes passed; no audit vulnerabilities | `/tmp/phase9-browser.log`, `/tmp/phase9-smoke-*.log`, `/tmp/phase9-bundler-audit.log` (local). Pinned Chromium download returned CDN HTTP 403; system Chrome used. |
| Independent Cable process | API A on 3001, native Rails API/Cable B on 3002, Playwright verifier | Passed auctions 186 and 194, revision 2 → hint/REST 3; stream isolation and malformed/disallowed-origin rejection | `/tmp/phase9-verify-realtime-final.log` (local). Initial run exposed obsolete exactly-one-hint assertion; delayed/duplicate current hints are allowed, verifier updated and web lint/format passed. |
| Multi-process closing | `scripts/smoke-closing` with closer paused and two API processes | Six scenarios passed: soft-close, stale closer, bid/close race, concurrent closers, expiry | `/tmp/phase9-smoke-closing.log` (local); closer restarted |
| Final publisher retry on PostgreSQL clock | Restart publisher with final code, stop Redis, commit auction 164 revision 5, restore Redis | Event `9e4b0cd8…` stayed pending through `RedisClient::CannotConnectError`, attempts 4; recovered at attempts 5, last error cleared, backlog 0, real worker completed JID `56be28de…` | Live Compose observations, 2026-09-30 13:29 UTC |

## Live observations and review targets

Auction 163's originating Rails process was killed after printing committed
price 10,000/revision 3 and three pending event UUIDs. A different Rails process
read all rows from PostgreSQL. A separate one-shot publisher then acknowledged
the rows; real Sidekiq worker logs showed three `AuctionChangedJob` completions.

During Redis outage, PostgreSQL answered `pg_isready` while the originating
process committed auction 164 and its events. Publisher failures changed only
outbox retry state. Restoring Redis drained the backlog and cleared last errors.
The auction command did not roll back. For event `b041fa99…`, Redis accepted the
first job immediately before publisher SIGKILL; acknowledgment rollback left the
same event publishable. The retry produced a second completed job. The job reads
the current revision, so duplicate work could not change price, leader or winner.

## Adversarial review

- **Atomicity:** Public domain methods call the outbox insert before their
  savepoint exits. The enclosing idempotency transaction owns the outcome.
  Failed insert and outer rollback specs prove no committed bid/revision/outbox
  mismatch. Direct privileged SQL is outside the application workflow contract.
- **Replay/no-op/privacy:** Replay never re-enters the domain write; sabotage D
  detected an added event. Private maximum, identical max, rejected bid and
  duplicate close remain silent. The schema has no private payload and logs
  include only event UUID, aggregate counts and error class.
- **Crash/retry:** API death and Redis outage leave pending work. Publisher row
  locks roll back on death. Enqueue/ack ambiguity can duplicate jobs; real
  worker and PostgreSQL revision checks passed. Two publishers skip locked rows
  and can process other rows; no global or per-auction delivery order is claimed.
- **Clock finding fixed:** Host `Time.current` previously set retry/ack times
  while the due predicate used PostgreSQL time. A skewed host could postpone a
  row substantially and distort age metrics. Retry, acknowledgment and age now
  read PostgreSQL `clock_timestamp()`; the one-year-skew spec and final live
  Redis recovery passed. An attempted Arel SQL assignment was typecast by
  ActiveRecord and made rows immediately due; focused specs caught it before
  the final code used explicit DB time reads. No mutant was retained.
- **Delivery limit:** `published_at` is successful Sidekiq enqueue, not worker,
  Cable or browser receipt. Redis loss after ack, Dead-set exhaustion and Cable
  failure remain possible. Pending poison rows retry indefinitely and require
  operator action. Redis network operations time out after two seconds, but a
  full cycle has no hard wall-clock deadline. Metrics are aggregate logs, without
  Phase 13 alerting or capacity evidence. Phase 10 Kafka scope remains untouched.
