# Phase 11 ExecPlan — Redis projection

Status: COMPLETE — verified 2026-09-30; final documentation/CI commit follows this plan.
Completed: Primary projection implementation `b88ad58`; live/failure campaign `25c7172`; broad backend, static/security, frontend, Compose/API and browser checks in the Evidence Index below. Phase 11 ADR, architecture and operator documentation are updated.
Remaining: No Phase 11 work. Phase 12 requires a separate explicit request.
Known limitations: The retained local Kafka topic contained a Phase 10 poison event at partition 1 offset 7; the new earliest-offset group stopped as designed. For the controlled local campaign, its offsets were reset to the topic tail and PostgreSQL rebuild covered skipped history. The explicit endpoint is eventual. Finite retention, publisher reorder and legacy rows constrain Kafka-only replay; PostgreSQL is the current-state rebuild source. A corrupt Redis key blocks write/seed until that key is deleted; the endpoint falls back. Full Redis flush used isolated DB 15; shared DB 0 had only its projection namespace removed. There is no production freshness, replay-time, capacity or HA claim.
Relevant files: `apps/api/app/services/{auction_public_projection,kafka_projection_consumer,kafka_event_codec}.rb`, `app/controllers/api/v1/auctions_controller.rb`, `bin/{kafka_projection_consumer,rebuild_auction_projections}`, `spec/integration/redis_projection_spec.rb`, `docker-compose.yml`, `apps/api/Gemfile{,.lock}`; prior public source: `app/models/{auction,outbox_event}.rb`, `app/presenters/api/v1/auction_presenter.rb`.
Relevant ADRs: [ADR-010](../adr/010-transactional-public-outbox.md), [ADR-011](../adr/011-kafka-domain-events.md); Phase 11 ADR to be added for the projection/read policy.

## Primary implementation checkpoint

Redis key `hammerfall:auction-public:v1:<auction_id>` stores schema version, auction ID, public revision, event ID (nil for PostgreSQL seed), occurrence time, Redis write time in milliseconds, source, exact public Kafka v1 data and its digest. The Lua write compares revisions atomically; higher replaces, equal/same digest is duplicate, lower is stale, equal/different digest is a hard conflict that leaves the offset uncommitted. The Kafka consumer validates the Phase 10 envelope, writes Redis, then synchronously commits offset. Redis failure and poison leave the offset uncommitted. The new `GET /api/v1/auctions/:id/public-state` reads this snapshot as an explicitly eventual lean view, exposing source and age. It falls back to PostgreSQL on miss, corruption or Redis error. Existing GET and all commands remain PostgreSQL-backed. The manual rebuild script seeds Redis from current PostgreSQL rows; no scheduled repair was added.

Focused test coverage uses real local PostgreSQL and Redis for public shape/freshness, duplicate/reordered/concurrent revisions, same-revision conflict, stale read vs PostgreSQL, Redis key loss/seed, poison, write outage, simulated post-write/pre-offset crash, read outage and rebuild privacy. Live campaign evidence follows.

The first focused command was run without sourcing `.env` and failed during Rails test schema connection (`PG::ConnectionBad: no password supplied`, no examples run). Sourcing `.env` resolved this; the focused suite then passed. No test was weakened.

## Live campaign and adversarial investigation

All live checks used Compose PostgreSQL, Kafka and Redis on 2026-09-30. Auction 226 was the controlled committed fixture. Public revisions and prices were: 3/10000, 4/11000, 5/12000, 6/13000. Kafka events for this auction were on partition 2 offsets 67–75. The consumer initially stopped on retained Phase 10 poison at partition 1 offset 7. Its local test group was reset to the topic tail (partition 1 offset 40, partition 2 offset 67) before new events were created. No production poison/offset policy was changed.

- Live publisher → broker → projection consumer: event `7c00d79d-1346-4d01-aa10-34b54aadedc8` yielded Redis revision 3, price 10000, source `kafka`; `/public-state` exposed `meta.source=redis`, event/projected timestamps and age. Ordinary GET read PostgreSQL. Revision 4 yielded price 11000 in both.
- Duplicate/stale: producer sent revision 4 twice and revision 1 after revision 4. Consumer logged `duplicate` at offsets 71–72 and `stale` at 73; Redis and both endpoint reads remained revision 4/11000. A same-revision conflict and poison remain covered by focused tests.
- Redis service stopped: a bid committed in PostgreSQL at revision 5/12000; both ordinary GET and eventual GET worked, with eventual `meta.source=postgresql`. The consumer failed at its Redis write with its offset uncommitted. After Redis and consumer restart, offset 74 was applied to Redis at revision 5/12000.
- Total projection loss: stopped consumer, removed all 24 `hammerfall:auction-public:v1:*` keys in shared DB 0, and saw PostgreSQL fallback at revision 5/12000. `bin/rebuild_auction_projections` seeded 181 current PostgreSQL auctions; key 226 held revision 5/12000, source `postgresql_seed`. Reset partition 2 offset to 67 and replayed offsets 67–74: older events were stale, revision 5 duplicate, key stayed at 5/12000, committed offset advanced to 75. Separately seeded isolated Redis DB 15 at revision 6, `FLUSHDB` cleared it to zero keys, PostgreSQL remained 6/13000, and a new seed restored 6/13000. DB 15 was flushed again after the check.
- Post-write/pre-offset crash: queued revision 6 at offset 75 with the group committed at 75. A temporary `exit!(86)` hook immediately after `apply_event` terminated a real consumer process. Redis held 6/13000 while Kafka remained at committed offset 75 with lag 1. Hook was removed; normal consumer restart logged `duplicate` for offset 75 and committed offset 76, lag 0. An initial SIGKILL hook did not trigger as intended and the event committed; the controlled offset/key were reset before the successful abrupt-exit run. No hook remains in the source.
- Two separate Rails processes applied revisions 5 and 6 concurrently to a deleted key; both returned `applied` in this schedule, and the final atomic Redis state was 6/13000. Focused thread checks and live broker stale replay cover the opposite ordering.
- Private maximum 20000 was committed for the leader without changing public revision 6 or adding an outbox event. Raw Redis remained revision 6/13000 and contained no maximum value/private field. A malformed Redis value produced PostgreSQL fallback 6/13000; deleting it and seeding restored the projection. This confirms manual key deletion is needed for corrupt-key repair.

Sabotage changes were temporary and restored: disabling the Lua stale guard made the focused stale test fail (`expected :stale, got :applied`); disabling equal-revision handling made duplicate and conflict tests fail (2/2); replacing controller fallback with `raise` failed the Redis-unavailable test; adding `maximum_amount` to seed data failed the new raw-Redis privacy test. Logs: `/tmp/hammerfall-p11-sabotage-{stale,duplicate,fallback,privacy}.log`. Post-restore suite: `/tmp/hammerfall-p11-post-sabotage.log`, 8 examples/0 failures, seed 50920. Production source has no sabotage diff.

Adversarial result: Redis loss did not lose PostgreSQL state or block bidding; stale/duplicate Kafka events and a post-write crash did not regress/corrupt the projection; fallback reported PostgreSQL as source and did not claim Redis freshness; private maximum stayed out of Redis; PostgreSQL rebuild plus replay converged. Remaining operational limits are poison-offset handling, finite Kafka retention, corrupt-key deletion and eventual staleness. No Phase 12 scheduled repair was added. Final review should revisit these conclusions after broad regression/docs.

## Decisions

- PostgreSQL `Auction` and its `AuctionPresenter` are the authoritative public REST representation. `public_revision` increments with public mutations in the auction transaction; draft creation begins at zero. The outbox event stores a public-only snapshot of the mutable fields, not REST `created_at`, `updated_at`, currency or ID.
- Kafka v1 identity is stable `event_id` UUID, `aggregate_id` decimal auction ID key and `aggregate_version` public revision. Duplicate IDs and same-revision conflicts must be safe; revisions can arrive out of order because publisher claims are concurrent. The audit group's PostgreSQL receipt is independent and cannot act as a Redis projection receipt.
- Use a separate Kafka projection consumer group. A single Redis key per auction will contain versioned public state and freshness metadata. An atomic compare-and-set operation will admit only a higher revision. A duplicate or stale revision cannot overwrite state. Unknown event shapes stop the offset as poison.
- Keep the existing REST auction endpoint PostgreSQL-backed. Add an explicit, lean eventual public-state read for callers that accept staleness; expose revision, source and age, and fall back to PostgreSQL on a miss or Redis failure. This is the justified Redis fast path and does not silently change existing REST consistency. Redis failure must only degrade reads, never auction commands.
- Redis loss after Kafka offset acknowledgment cannot be fully rebuilt from Kafka retention alone. The recovery procedure must use authoritative PostgreSQL as a current-state seed or explicitly require retained complete event coverage; no Phase 12 scheduled repair or reconciliation is introduced.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Phase 10 boundary inspection | Targeted `Auction#persist_public_change!`, outbox/envelope, codec, audit consumer and focused Kafka spec | One public-only snapshot per revision; independent audit group; publisher concurrency can reorder | ADR-011 and source paths above |
| PostgreSQL public representation | Targeted `AuctionPresenter`, `AuctionsController`, request spec | REST has ID/revision, public terms/state, currency and timestamps; revision zero drafts have no event | Source paths above |
| Phase 11 focused checks | `source ../../.env; bundle exec rspec spec/integration/redis_projection_spec.rb spec/integration/kafka_outbox_spec.rb` in `apps/api` | 20 examples, 0 failures, seed 41577 | Real local PostgreSQL/Redis; 7 new projection examples and prior Kafka contract examples |
| Autoload and changed Ruby lint | `bin/rails zeitwerk:check`; `bundle exec rubocop` on six changed Ruby files | Autoload good; 6 files, 0 offenses | Local output 2026-09-30 |
| Compose config and whitespace | `docker compose config -q`; `git diff --check` | Both exit 0 | Local output 2026-09-30 |
| Live Kafka and endpoint | Compose projection consumer, committed auction 226, direct GET and raw Redis | Revision 3/10000 then 4/11000; metadata present | Live campaign above; partition 2 offsets 67–70 |
| Duplicate/stale and replay | Produce 4,4,1; reset partition 2 to 67 after PostgreSQL seed | Duplicate at 71–72, stale at 73; replay stale 67–73, duplicate 74; key stayed 5/12000 | Consumer logs; committed offset 75 |
| Redis outage and recovery | Stop/start Compose Redis; bid through Rails; GET; restart consumer | PostgreSQL bid 5/12000; endpoint fallback; uncommitted write replayed/applied offset 74 | Live campaign above |
| Total projection loss and rebuild | Delete all 24 projection keys; run rebuild; isolated DB 15 `FLUSHDB` | Fallback 5/12000; 181 PostgreSQL seeds; isolated full DB loss and restore 6/13000 | Live campaign above |
| Real abrupt process exit | Temporary `exit!(86)` after Redis write at offset 75; restore/restart | Redis 6/13000 with group lag 1; duplicate replay, offset 76/lag 0 | Live campaign above |
| Concurrent and privacy checks | Two Rails processes; private maximum 20000; corrupt Redis value | Final revision 6; maximum absent; malformed-value fallback and seed recovery | Live campaign above |
| Sabotage | Four temporary mutations and focused RSpec | Expected failures for stale, duplicate/conflict, fallback and privacy; all restored | `/tmp/hammerfall-p11-sabotage-*.log` |
| Post-sabotage focused suite and lint | RSpec projection spec, RuboCop test file, `git diff --check` | 8 examples/0 failures seed 50920; 1 file/0 offenses; whitespace clean | `/tmp/hammerfall-p11-post-sabotage.log` |
| Full backend regression | `set -a; source ../../.env; set +a; bundle exec rspec` in `apps/api` | 389 examples, 0 failures, seed 56291, real PostgreSQL/Redis | `/tmp/hammerfall-p11-final-rspec.log` |
| Ruby static and security | `bundle exec rubocop`; `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`; `bin/bundler-audit` | 101 files/0 offenses; 0 warnings; no known vulnerabilities in checked database | `/tmp/hammerfall-p11-final-{rubocop,brakeman,bundler-audit}.log` |
| Frontend regression and production build | `npm test`; `npm run lint`; `npm run format:check`; `npm run typecheck`; `npm run build` | 73 tests passed; lint/format/types/build passed | `/tmp/hammerfall-p11-final-web-{test,lint,format,typecheck,build}.log` |
| Compose build and startup | `docker compose config -q`; `docker compose up --build --wait --wait-timeout 360` | Rebuilt API and web; PostgreSQL, Kafka, Redis, API, web and worker/consumer roles healthy | `/tmp/hammerfall-p11-final-compose-build.log` |
| CI-style local runtime smokes | HTTP `/up` and web `/`; Redis PING; Kafka topic; scheduler, both publishers, Kafka smoke, API, closer, concurrent/proxy bid and idempotency prune scripts | All exited 0; Kafka smoke auction 227 revision 3, 3 events; concurrent/proxy HTTP passed | `/tmp/hammerfall-p11-final-{redis-ping,kafka-topic,scheduler,outbox,kafka-publisher,smoke-kafka,smoke-api,closer,smoke-concurrent,smoke-proxy,prune}.log` |
| Final integrated projection read | Compose auction 227: Rails PostgreSQL/outbox inspection, Redis read, ordinary and eventual HTTP GET | PostgreSQL revision 3/10000; 3 outbox rows broker-acknowledged; Redis Kafka source revision 3/10000; both GETs 200 at revision 3/10000, eventual source `redis` | Local output 2026-09-30; consumer applied events in Compose logs |
| Real browser | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` | 7 passed: bidding/retry/privacy, closing, responsive views, lifecycle, Cable recovery, soft close and autonomous closer | `/tmp/hammerfall-p11-final-playwright-chrome.log` |
| Documentation and final review | ADR-012, architecture/API/failure/runbook/learning/code-map/security/progress/handoff updates; local Markdown link check; `git diff --check`; adversarial table below | Local links resolve; whitespace clean; no known serious Phase 11 correctness defect | This plan and changed documents; Git diff |

Finalization setup notes: the first broad RSpec command sourced `.env` without
exporting it, so PostgreSQL authentication failed before any examples; rerunning
with `set -a` passed. Playwright's bundled browser was absent. Its download
returned CDN HTTP 403 for this location, so the documented
`PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome` option was used. Neither
failure represents an application test failure.

## Final adversarial review

| Challenge | Finding / evidence |
| --- | --- |
| Stale or reordered Kafka data regresses Redis | Atomic Lua revision comparison rejects a lower revision; focused test, live replay and stale-guard sabotage proved the check is active. |
| Duplicate delivery or post-write consumer crash changes state | Equal revision/data is a no-op. Focused tests and live abrupt exit/restart showed Redis retained revision 6 while the uncommitted offset replayed as duplicate. |
| Redis outage or total loss changes bid correctness or destroys state | Commands, ordinary GET, idempotency and auction locks use PostgreSQL. Live bid during outage committed; total namespace loss and isolated full DB flush left PostgreSQL intact. |
| A newer projection contains older public state | `Auction#persist_public_change!` saves the public snapshot and revision on the same outbox row within the locked auction transaction; codec validates the shape; Redis compares that revision. No independent read is used to construct a Kafka snapshot. This is an internal pipeline guarantee, not protection against a forged trusted-broker record. |
| Fallback mislabels its authority | Redis hit returns `meta.source=redis`; miss, invalid value or connection failure builds data from `AuctionPresenter` and returns `meta.source=postgresql`. Focused and live outage/corruption checks passed. A well-formed stale Redis hit deliberately stays eventual. |
| Private maximum, priority, origin or idempotency data leaks | Kafka v1 exact data allowlist and PostgreSQL seed allowlist omit these fields. Focused raw-key checks, live private-maximum update and privacy sabotage passed; no auth secrecy is claimed. |
| Rebuild disagrees with current PostgreSQL or replay overwrites it | Seed uses current presenter data and the same atomic revision rule. Live seed matched PostgreSQL 5/12000 and 6/13000; replay of older events stayed stale and equal event was duplicate. Manual rebuild is not a simultaneous cross-row snapshot and does not automatically repair a valid same-revision conflict. |
| An application path depends on Redis for auction authority or Phase 12 work appeared early | Source routing keeps `show` and all command paths on PostgreSQL; only explicit `public_state` and background projection use Redis. No scheduled projection comparison/repair was added; the preexisting read-only PostgreSQL sweep is separate. |

Review outcome: no known serious Phase 11 correctness bug. Operational limits
remain: finite retention, poison-offset review, potential unbounded projection
staleness, manual rebuild after loss, single-key deletion for corruption,
unauthenticated demo API and unmeasured production capacity/availability.
