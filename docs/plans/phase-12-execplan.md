# Phase 12 ExecPlan — projection reconciliation

Status: Complete — verified 2026-10-01. Phase 13 has not started.
Current milestone: Phase 12 implementation, live campaign, overlap repair, broad regression and durable documentation complete.
Completed: PostgreSQL-authoritative Redis comparison/repair (`ceb3d04`), live failure/sabotage campaign (`3b7e64f`), and database-clock lease with token/cursor fencing for both scheduled scan types (`6f8f94b`). The old PostgreSQL sweep stays read-only. A browser test now waits for its asynchronous Cable hint. No auction command, Kafka consumer or atomic Redis projection writer code changed.
Verified: 19 live Phase 12 examples with real PostgreSQL/Redis/Kafka, 0 failures (seed 62495); 20 lease/scheduler focused examples, 0 failures (seed 47932); full backend 410 examples/0 failures/2 intentional Kafka pending (seed 28745); RuboCop 108 files/0 offenses; Brakeman 0 warnings, bundler-audit no vulnerabilities, Zeitwerk passed. Frontend 73 Vitest tests, lint/format/types/build, Compose and smokes passed; final real-browser run 7/7 with system Chrome. Evidence below.
Remaining: No Phase 12 work. Phase 13 and the separate Phase 0–11 hardening pass require explicit user requests.
Known failures/limitations: Valid stale Redis state may persist until a successful scan; corrupt/equal-conflicting/ahead keys require review. Lost continuation after cursor advancement can delay a fresh scan until the ten-minute lease expires. Per-batch structured log counts are not exported Prometheus counters; no finite convergence, production capacity or HA guarantee is claimed. Hosted CI was not run. The local Playwright CDN returned a location-based 403; final browser checks used installed system Chrome.
Relevant files: `apps/api/app/services/{auction_public_projection,auction_projection_reconciler,reconciliation_scheduler,kafka_projection_consumer}.rb`, `app/jobs/{auction_projection_reconciliation_job,reconciliation_sweep_job}.rb`, `spec/integration/{auction_projection_reconciliation,auction_projection_reconciliation_live,redis_projection}_spec.rb`, `spec/jobs/reconciliation_sweep_job_spec.rb`.
Relevant ADRs: [ADR-012](../adr/012-redis-public-projection.md), [ADR-013](../adr/013-bounded-reconciliation-scan-ownership.md).
Next-session starting point: Do not continue Phase 12 or begin Phase 13 without a new explicit request. The [latest handoff](../handoffs/latest.md) and [progress record](../progress.md) give the phase boundary and limits.

## Decisions

- Authority: compare PostgreSQL `Auction.public_revision` and the exact `KafkaEventCodec::DATA_KEYS` public presenter fields against the validated Redis envelope. PostgreSQL is read independently of Redis; Redis never decides bidding, closure or winner.
- Drift model: missing and valid lower-revision keys are safe to seed from PostgreSQL. Equal revision with identical public data is healthy regardless of source/write time. Equal revision with different data, Redis ahead of PostgreSQL after a fresh check, and malformed/digest-invalid keys require operator review; do not silently overwrite them. Redis or PostgreSQL unavailability is reported and retried, not treated as drift.
- Repair uses the existing atomic Redis revision/digest Lua operation. It is safe against duplicate work and a concurrently delivered higher revision. A concurrent equal conflict is escalated. No auction row lock is needed for a derived-state snapshot; a later PostgreSQL change may make a just-written seed stale until Kafka delivery or the next scan.
- Keep the existing read-only PostgreSQL sweep distinct. Each job handles at most 100 ID-ordered rows under a fixed ceiling. Both scheduled scan types use independent PostgreSQL leases with database-clock expiry and token/cursor fencing; no transaction spans a scan chain. A failed queue handoff can require lease expiry and restart from ID zero. See ADR-013. Counters are per-batch structured log deltas with required names; Phase 13 can add an exporter.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Phase 11 path and authority | Targeted source, ADR-012, Phase 11 handoff and ExecPlan | Revision/digest Lua guard, PostgreSQL seed and explicit eventual read confirmed | `auction_public_projection.rb`, `kafka_projection_consumer.rb`, Phase 11 ExecPlan |
| Phase 12 focused tests | `bundle exec rspec spec/integration/auction_projection_reconciliation_spec.rb spec/jobs/reconciliation_sweep_job_spec.rb` | 14 examples, 0 failures, seed 59735 | `/tmp/hammerfall-p12-focused.log`; real local PostgreSQL/Redis |
| Focused Ruby lint | `bundle exec rubocop` on 5 changed Ruby files | 5 files, 0 offenses | `/tmp/hammerfall-p12-rubocop.log` |
| Whitespace | `git diff --check` | Clean | Local command 2026-10-01 |
| Drift/review and repeat | `PHASE12_LIVE_KAFKA=1 REDIS_URL=.../1 bundle exec rspec` on 3 Phase 12 specs | 19 examples, 0 failures; seed 62495. Missing/behind repair; equal healthy byte-identical on repeat; equal conflict/ahead/corrupt unchanged and reviewed | `/tmp/hammerfall-p12-campaign-final.log`; test files |
| Real Kafka race | Two gated examples; dedicated `hammerfall.phase12.verify` topic, real Rdkafka producer/consumer, PostgreSQL and Redis | N+1 broker delivery before N repair returned `:raced`, retained N+1; reverse order applied N then N+1 and converged | Same log; `auction_projection_reconciliation_live_spec.rb` |
| Concurrent reconcilers/crash | Two threads with separate Redis clients synchronize before seed; inject crash immediately after Redis write | Both repairs safe (`applied`/`duplicate`), later check healthy; crash retry healthy | Same log; final crash example `/tmp/hammerfall-p12-crash-final.log` |
| Bounded scan/scheduler | 101-row test and Compose scheduler restart on 196 development auctions | First test page 100, continuation 1; live Compose pages 100 and 96 under fixed ceiling 241; SQL `ORDER BY id ASC LIMIT 100`; scheduled Sidekiq jobs completed | Same log; `apps/api/log/{test,development}.log`; `/tmp/hammerfall-p12-compose-restart.log` |
| Redis outage/recovery | Pause actual Compose Redis; `RAILS_ENV=test bin/rails runner /tmp/hammerfall-p12-outage.rb`; unpause and rerun | Bid committed in PostgreSQL at revision 3/price 10000; reconciliation raised `ProjectionUnavailable` and logged unavailable=1; recovery seeded Redis revision 3 from PostgreSQL | `/tmp/hammerfall-p12-{redis-outage,redis-recovery}.log`; test log auction 1874 |
| PostgreSQL outage | Stop actual Compose DB; run same isolated runner; restart DB | `ActiveRecord::DatabaseConnectionError`; `postgresql_unavailable` log; Redis raw value unchanged | `/tmp/hammerfall-p12-pg-outage.log`; test log |
| Sabotage A–D | Temporary source mutations, focused tests, restore byte-for-byte | A stale overwrite 1 failure (`:repaired` vs `:raced`); B equal conflict overwrite 1 failure; C stale Redis accepted as healthy 1 failure; D direct SET seed 1 failure; source restored | `/tmp/hammerfall-p12-sabotage-{A,B,C,D}.log` |
| Operator/metric visibility | Focused assertions and live Rails logs | Explicit checked/healthy/drift/attempt/repair/failure/unavailable/review counters; operator log includes kind and ID, excludes private fields; no ID metric label | Phase 12 specs; `apps/api/log/{test,development}.log` |
| CI mode and Ruby lint | Kafka flag absent, live spec; RuboCop changed Ruby | 5 examples, 0 failures, 2 explicit Kafka pending; 3 files/0 offenses | `/tmp/hammerfall-p12-ci-mode.log`; `/tmp/hammerfall-p12-campaign-rubocop.log` |
| Scheduler lease and cursor fence | Real PostgreSQL/Redis focused specs on lease, jobs and reconciler | 20 examples, 0 failures, seed 47932; multiple schedulers/ticks, completion, expiry, duplicate retry, failed enqueue and bid independence | `/tmp/hammerfall-p12-lease-focused.log`; `reconciliation_lease_spec.rb` |
| Cursor-fence sabotage | Temporarily bypass cursor predicates in lease renew/advance, run post-advance crash example, restore byte-for-byte | 1 expected failure, then 1/0 after restoration | `/tmp/hammerfall-p12-lease-sabotage.log`; `/tmp/hammerfall-p12-lease-sabotage-restored.log` |
| New scheduler outage boundaries | Pause actual Redis, then stop actual PostgreSQL around one-shot test runner; restore both | Redis enqueue error released claim (`remaining_leases=0`); DB outage raised `ActiveRecord::DatabaseConnectionError` before scheduling | `/tmp/hammerfall-p12-lease-{redis,pg}-outage.log` |
| Full backend regression | `REDIS_URL=.../1 bundle exec rspec` | 410 examples, 0 failures, 2 intentional live Kafka pending; seed 28745 | `/tmp/hammerfall-p12-full-rspec.log` |
| Backend static/security | `bundle exec rubocop`; `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`; `bin/bundler-audit`; `bin/rails zeitwerk:check` | 108 files/0 offenses; 0 warnings; no vulnerabilities; Zeitwerk passed | `/tmp/hammerfall-p12-{full-rubocop,brakeman,audit,zeitwerk}.log` |
| Frontend and build | `npm run lint`, `format:check`, `typecheck`, `test`, `build` | All passed; Vitest 73/73; Next production build succeeded | `/tmp/hammerfall-p12-web-{lint,format,typecheck,test,build}.log` |
| Compose/runtime | `docker compose config --quiet`; `up --build --wait`; health, Redis/Kafka, scheduler, Kafka/API/concurrent/proxy, publishers and closer smokes | All services healthy; smoke commands passed; scheduler acquired/released both leases | `/tmp/hammerfall-p12-compose-up.log`; `/tmp/hammerfall-p12-smoke-*.log`; Compose/Rails logs |
| Browser/E2E | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` | 7/7 final. Initial full runs 6/7 because closer test asserted Cable hint immediately after REST/UI close; bounded polling fixed test timing. CDN browser download 403 in this location | `/tmp/hammerfall-p12-web-e2e-final.log`; initial/isolated logs |

## Primary implementation checkpoint

The checker reads a PostgreSQL auction snapshot and validates the Redis envelope using the existing strict projection reader. It compares `public_revision` and every `KafkaEventCodec::DATA_KEYS` field, ignoring source/event/write metadata for equality. Missing and valid lower revisions call the existing PostgreSQL seed, whose atomic Redis Lua guard accepts only a higher revision or identical equal content. A concurrent higher write returns `stale`; a concurrent equal conflict is logged as repair failure and operator review. A same-revision public mismatch, malformed/digest-invalid key or key ahead of a freshly reloaded PostgreSQL row is logged for operator review without mutation. Redis failure raises for Sidekiq retry. PostgreSQL failure also raises and logs its error class. Neither path changes an auction row.

The scheduler now enqueues the old read-only PostgreSQL sweep plus the new projection scan. Projection jobs read up to 100 auctions in ID order under a fixed max-ID ceiling, emit per-batch structured JSON counters and enqueue the next cursor only after completing the batch. Counters use the required drift/repair/failure names plus attempted, checked, unavailable and operator review. Identifiers appear only in per-auction logs, never as metric labels. Repeated scheduler runs can overlap; the Redis atomic guard makes duplicate repairs safe. No global lock or bid-path dependency was added.

The primary implementation's focused tests deliberately created missing, stale, equal-content, equal-conflict, ahead, malformed and digest-corrupt keys, plus a conflict arriving between detection and seed. They covered idempotent repeat, stale replay rejection, Redis read outage, job metric counts and unchanged PostgreSQL state. The scheduler spec verified both jobs were enqueued. The next section records the subsequent live campaign.

## Live campaign and adversarial review

The campaign used the test PostgreSQL database and Redis DB 1. Two Kafka race examples used the real broker and a dedicated one-partition topic `hammerfall.phase12.verify`, created with `docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --create --if-not-exists --topic hammerfall.phase12.verify --partitions 1 --replication-factor 1`. Set `PHASE12_LIVE_KAFKA=1` for these examples; ordinary backend CI has PostgreSQL/Redis but no Kafka, so they explicitly skip in normal suite runs. The first attempted live run on Redis DB 0/default Kafka topic failed because the running development projection consumer wrote the test auction key first; no product defect was inferred. Isolation fixed the test and all 19 examples then passed. The temporary outage fixture was removed, and both paused/stopped services were restored healthy.

Adversarial conclusions:

- A repair based on PostgreSQL revision N cannot lower Redis N+1: the live Kafka-before-repair test returned `:raced`; sabotage of the Lua higher-revision guard made that test fail. Kafka-after-repair advanced N to N+1.
- Two independent reconcilers can both attempt the same missing key; the Lua operation gives `applied` then `duplicate`, and repeated checks are healthy. A crash after the Redis write leaves a valid key; the next run is healthy. No exactly-once claim is made.
- Redis did not affect the accepted bid during its actual outage. PostgreSQL outage prevented comparison and caused no Redis mutation. Neither failure was turned into a successful repair. Sidekiq retry and the next scheduled scan provide later opportunities; logs carry error class, and unavailable batches carry a count. Repair-write failures are separately counted by existing focused tests.
- Equal-revision conflicting, ahead, malformed and digest-invalid projections remain unchanged for operator review. Sabotage of the equal-revision guard made the between-detection-and-seed safety test fail. Suppressing stale repair made the behind test fail. Direct `SET` in `seed` made the Kafka race fail. All sabotage source edits were restored byte-for-byte and are absent from the commit.
- Job work is bounded by an ID cursor, fixed max-ID ceiling and `LIMIT 100`. The 101-row test and 196-row live scheduler run proved continuation. This campaign exposed an operational issue: independent ticks could start duplicate chains under sustained backlog. The finalization section records the lease/cursor repair.
- Batch logs now report `checked` and explicit `healthy`, plus named drift, repair attempt, repair and repair-failure counters, unavailable and operator-review counts. No metric label includes auction or event IDs. Per-auction logs include ID, state/result and error class but no public payload, private maximum, priority, bid origin or idempotency material. These log counters need a documented collection/aggregation procedure; a Prometheus exporter belongs to Phase 13.
- No Phase 13 tracing/dashboard implementation or separate Phase 0–11 hardening change was introduced. Ordinary authoritative reads remain PostgreSQL based; the explicit eventual public-state endpoint keeps its Phase 11 behavior.

## Scheduler repair and final adversarial closure

ADR-013 records why a PostgreSQL lease was chosen over a process-local flag,
Redis uniqueness or a connection-held advisory lock. Each scan type has one
database-clock lease and owner token. Jobs renew it every 25 rows and at page
boundaries. Cursor compare-and-advance permits only one successor handoff per
page, including under Sidekiq replay. A dead owner or a crash after cursor
advance but before enqueue leaves an expiring lease; a later tick reclaims it
and starts from ID zero. Final pages delete only their own token/cursor row.
Manual tokenless jobs remain explicitly uncoordinated operator actions.

Final challenge results: parallel claims produced one owner; repeat ticks
queued one chain per type; a bid committed while both leases were held;
completion permitted new claims; expiration fenced an old queued page; a
duplicate page could not branch after handoff; and Redis/PG outages failed
without leaving permanent ownership. A temporary removal of cursor predicates
made the targeted test fail and was restored. Each job still has a 100-row
bound, no auction lock and no long transaction. A frozen worker may finish
part of one page after its lease expires; it cannot extend that old chain.
PostgreSQL remains the only auction authority. Kafka/repair race, concurrent
repair, operator-review and privacy behavior from the live campaign were
preserved by the full regression. Metric labels remain fixed-cardinality;
auction IDs occur only in diagnostic logs. No Phase 13 exporter or tracing
was added.

The final browser run exposed and resolved a test timing assumption, not an
auction state defect: REST/countdown could show the closed winner before the
asynchronous Cable hint arrived. The test now waits up to ten seconds for
the actual hint and the full seven-scenario run passes. This change does not
alter frontend runtime behavior.
