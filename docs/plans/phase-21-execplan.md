# Phase 21 ExecPlan — Marketplace trust and auction policy

Status: Complete — local and hosted implementation gates passed; Phase 22 not started.
Current milestone: Phase boundary and archived evidence. The closure documentation commit is checked on its exact SHA in the final response.
Completed: Session 1 research/stepped increments; [Session 2 reserve](../marketplace/phase-21-session-2.md); Session 3 persisted regular/rapid policy, locked deadline arithmetic, v2 compatibility including earlier Redis values, combined contention/retry tests, public UI and live replica/Kafka/Redis/rebuild proof. See [final report](../marketplace/phase-21-final.md).
Verified: Final backend 554 examples/0 failures/4 opt-in pending, Redis DB 15/pool 15, seed 33589; five rapid race seeds; 78 frontend tests plus typecheck/lint/format/build; RuboCop 173 files/0 offenses, Zeitwerk, Brakeman 0 warnings and bundler-audit clean; migration rollback/reapply and populated-data downgrade guards; live combined smoke auction 771/closed revision 5; full browser 9 passed/1 historical opt-in skipped. See Evidence Index.
Remaining: None for Phase 21. Do not start Phase 22 without an explicit request.
Known failures/limitations: First complete browser run had one fixture expire during a 60-second lifecycle quota retry; timed fixtures now allow admission headroom then wait into the actual window. Earlier Redis v2 equal-revision compatibility issue fixed and regression-tested. Stepped `minimum_increment` create input remains required but ignored by pricing. Active reserve lowering/removal, seller management UI, payment and post-auction offers remain deferred.
Relevant files: `apps/api/app/models/auction.rb`, `apps/api/app/models/bidding/{bid_increment_policy,proxy_resolver}.rb`, `apps/api/app/models/public_auction_snapshot.rb`, `apps/api/app/services/{kafka_event_codec,auction_public_projection,auction_projection_reconciler}.rb`, migrations `20261004020000` and `20261005010000`, frontend auction components and reserve/integration specs.
Relevant ADRs: [ADR-003](../adr/003-auction-concurrency-control.md), [ADR-004](../adr/004-proxy-bidding.md), [ADR-005](../adr/005-auction-deadlines-and-soft-close.md), [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-018](../adr/018-stepped-bid-increments.md), [ADR-019](../adr/019-hidden-reserve-policy.md), [ADR-020](../adr/020-auction-closing-policies.md).
Next-session starting point: Phase 21 is closed. Read the [latest handoff](../handoffs/latest.md) and [final report](../marketplace/phase-21-final.md) only for a requested follow-up or a new phase.

## Decisions

- Session 2 async contract: INTRODUCE v2. The v1 Kafka/Redis validator requires exact public fields and v1 winner semantics, so new domain snapshots use `.v2` types and `schema_version=2`. Consumers still decode retained v1 events as historical no-reserve state and normalize to `reserve_status=none`; Redis uses a v2 key, with PostgreSQL seed/reconciliation restoring current state. Cable remains an unchanged `auction.changed.v1` invalidation. The Kafka topic and consumer groups retain their offsets/replay order. Deploy migration/readers and drain old writers/consumers before enabling reserve writers.
- ADOPT price band increments, private reserve, and a rapid closing policy. Each has a direct locked-state or deadline invariant and first-party public evidence. All three are implemented.
- Session 3 retains public schema v2 with an optional historical closing-policy field that normalizes to regular. Earlier Redis v2 values validate their original digest before normalization; only equivalent regular equal-revision writes may upgrade them. New snapshots and PostgreSQL rebuilds always carry the persisted mode. Cable stays v1 invalidation. Migration downgrade refuses rapid rows or emitted policy events.
- SATISFIED BY PHASE 20: seller self-bid rejection, after the auction lock and authenticated actor resolution.
- DEFER account/country/category restrictions and bid reservations: meaningful versions require signals, payment holds, and rules absent from this case study.
- REJECT the lightweight bidding-panel experiment for Phase 21: it does not strengthen proof of auction policy and would require separate consent, retention and analytics semantics.
- Existing auctions retain their fixed increment. A new opt-in stepped schedule is a Hammerfall approximation of the current published Catawiki table; their help article warns that some lots differ due to experiments. Reserve and rapid closing designs will also be explicit Hammerfall approximations.

## Evidence Index

The local runtime restarted during the interrupted final browser run. Earlier
`/tmp` logs are no longer present; their observed commands/results remain recorded
below. Unfinished browser runs are not counted as passes. Resumed gate logs live
under ignored `apps/api/tmp/phase21-final-gate/`.

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Public rules | First-party Catawiki Help Centre and policy pages, 2026-10-04 | Captured | [Session 1 report](../marketplace/phase-21-session-1.md) |
| Migration | `RAILS_ENV=test bin/rails db:migrate` with local `.env` | Exit 0 | Added `increment_policy` default `fixed` and CHECK in test PostgreSQL |
| Initial focused backend | 5 affected model/request/concurrency specs | 95 examples, 0 failures | `/tmp/phase21-focused.log`, seed 52230 |
| Redis isolation diagnosis | 2 projection/reconciliation specs with `REDIS_URL=redis://127.0.0.1:6379/15` | 20 examples, 0 failures | `/tmp/phase21-projection-isolated.log`, seed 41380; shared DB 0 had stale test-ID keys |
| Wider affected backend | 14 model/request/integration specs, isolated Redis DB 15, pool 15 | 264 examples, 0 failures, 1 pending | `/tmp/phase21-broad-focused-isolated.log`, seed 11240; pending is opt-in live Kafka |
| Final changed tests | Increment, idempotency, concurrent-bidding specs after test additions | 36 examples, 0 failures | `/tmp/phase21-final-focused.log`, seed 6380 |
| Repeated increment race | `rspec spec/integration/concurrent_bidding_spec.rb:68 --seed N`, N=1..5 | 5 runs × 1 example, 0 failures | `/tmp/phase21-race-1.log` through `-5.log`; both serial outcomes permitted |
| Ruby lint | `bundle exec rubocop` on 9 changed Ruby files | 9 inspected, 0 offenses | `/tmp/phase21-rubocop.log` |
| Diff check | `git diff --check` | Exit 0 | No whitespace errors |
| Reserve migration and downgrade | `RAILS_ENV=test bin/rails db:migrate`, `db:rollback STEP=1`, then migrate with local `.env` | All exit 0 | Nullable private column, conditional SQL winner and version constraints; rollback only after confirming zero reserve/v2 rows |
| Reserve focused integration | 7 reserve/model/request/contention/SQL/projection specs, Redis DB 15 | 103 examples, 0 failures | `/tmp/phase21-reserve-integration.log`, seed in log; initial SQL test fixture placement fixed |
| Reserve affected backend regression | 18 model/request/integration specs, `REDIS_URL=redis://127.0.0.1:6379/15 RAILS_MAX_THREADS=15 OTEL_ENABLED=false` | 311 examples, 0 failures, 2 pending | `/tmp/phase21-reserve-final-affected.log`; pending trace opt-in and live broker opt-in |
| Reserve contention repetition | `rspec spec/integration/concurrent_maximum_bidding_spec.rb:53 --seed N`, N=11,23,37,41,59 | 5 runs × 1 example, 0 failures | `/tmp/phase21-reserve-race-N.log` |
| Frontend tests | `npm test -- --run` relevant reads/commands/client specs | 33 tests, 0 failures | `/tmp/phase21-reserve-web.log` |
| Frontend static/build | `npm run typecheck`, `npm run lint`, `npm run build` | All exit 0 | `/tmp/phase21-reserve-web-{typecheck,lint,build}.log` |
| Ruby lint/loading | RuboCop 20 changed Ruby files; `RAILS_ENV=test bin/rails zeitwerk:check` | 0 offenses; eager load good | `/tmp/phase21-reserve-rubocop.log`, `/tmp/phase21-reserve-zeitwerk.log` |
| Reserve privacy | API/outbox/Kafka/Redis/Cable/model/log assertions | Included in above backend runs | `spec/requests/reserve_privacy_spec.rb`, `spec/integration/{kafka_outbox,redis_projection}_spec.rb` |
| Rapid migration | Test `db:migrate`, `db:rollback STEP=1`, reapply; Compose development migrate | Exit 0 | Default regular, SQL mode constraint; no rapid/policy-event data present during safe downgrade |
| Rapid focused checks | Deadline, rapid model, auction API and Redis specs | 56 examples, 0 failures, seed 44010 | Initial implementation check |
| Rapid retry/race/codec | Rapid PostgreSQL races, idempotency API, Kafka outbox specs | 50 examples, 0 failures, 2 opt-in pending, seed 19274 | Lost response replay and both lock orders |
| Repeated rapid races | `rspec spec/integration/rapid_closing_race_spec.rb --seed N`, N=11,23,37,41,59 | 5 × 3 examples, 0 failures | `/tmp/phase21-rapid-race-N.log` |
| Rapid combined final selection | Rapid models and race specs | 10 examples, 0 failures, seed 62894 | `/tmp/phase21-rapid-final.log`; genuine repeated extension, stale stepped minimum, reserve/proxy cases |
| Legacy Redis v2 compatibility | Redis projection and reconciliation specs | 24 examples, 0 failures, seed 29187 | `/tmp/phase21-compatibility.log`; subsequent negative conflict assertion included in full suite |
| Full final backend | `REDIS_URL=redis://127.0.0.1:6379/15 RAILS_MAX_THREADS=15 OTEL_ENABLED=false bundle exec rspec` with local `.env` | 549 examples, 0 failures, 4 pending, seed 5927 | `/tmp/phase21-full-final-rspec.log`; pending historical live Kafka/trace opt-ins |
| Full frontend | `npm run typecheck`, `lint`, `format:check`, `test`, `build` | All exit 0; 78 tests | Final local gate after rapid UI and strict mode validation |
| Ruby/security | `bundle exec rubocop`, test `zeitwerk:check`, `brakeman -q`, `bundler-audit check --update` | 173 files/0 offenses; eager load passed; 0 warnings; no advisories | Final local gate |
| Live combined async/replica proof | `docker compose exec -T api ruby script/phase21_final.rb` | PASS, auction 738/revision 4 | B accepted late maximum; A replay; +10 once; €650/met; real Kafka/Redis and exact PostgreSQL rebuild |
| Targeted real browser | Playwright `--grep 'rapid reserve auction'` | 1 passed, 48.7 seconds | `/tmp/phase21-browser-rapid.log`; authenticated maximum, Cable/REST extended deadline, sold outcome |
| First full browser attempt | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` | 8 passed, 1 failed, 1 opt-in skipped | `/tmp/phase21-browser-full.log`; regular 30-second fixture expired during real 60-second quota retry, repaired with setup headroom and real-window wait |
| Resumed Compose startup | `docker compose up -d --build --wait --wait-timeout 360` | Exit 0, required roles healthy | `apps/api/tmp/phase21-final-gate/compose-start.log` |
| Backend after additional combined/replay assertions | `REDIS_URL=redis://127.0.0.1:6379/15 RAILS_MAX_THREADS=15 OTEL_ENABLED=false bundle exec rspec` with local `.env` | 552 examples, 0 failures, 4 opt-in pending, seed 5937 | Observed before final security assertions; both manual/maximum lost-response replay and reserve-crossing repeated extension included |
| Final schema/lint | Test `db:prepare`; `bundle exec rubocop` | Exit 0; 173 files, 0 offenses | `apps/api/tmp/phase21-final-gate/{schema,rubocop}.log` |
| Populated downgrade guards | Rollback-only test transactions with a rapid row, then a regular row plus policy event | Both refused downgrade; no persistent fixture data | Migration guard verified independently of empty rollback/reapply |
| Resumed authenticated API/Kafka/role smoke | `scripts/smoke-api`, `scripts/smoke-kafka`, closer and reconciliation scheduler `--once` in Compose | PASS; API auction 760, Kafka auction 761/revision 3, both one-shots exit 0 | `apps/api/tmp/phase21-final-gate/{api-smoke,kafka-smoke,closer,reconciliation}.log` |
| Documentation hygiene | Changed Markdown relative-link check; `git diff --check` | No missing relative targets or whitespace errors | Final documentation review |
| Final full browser | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` | 9 passed, 1 historical opt-in skipped; 8.5 minutes | `apps/api/tmp/phase21-final-gate/browser.log`; rapid reserve/stepped deadline, displayed minimum, final winner, regular soft close, retry/security/realtime regressions |
| Final combined policy closure | `docker compose exec -T api ruby script/phase21_final.rb` | PASS; auction 771, closed revision 5, winner 4131 | `apps/api/tmp/phase21-final-gate/policy-final.log`; A accepts, B reads/replays; one +10 extension, €650/met, autonomous sold close, real Kafka/Redis delivery and exact PostgreSQL rebuild |
| Security/deadline assertion repair | Explicit anonymous manual/maximum and rate-limited rapid command assertions | 15 request examples, 0 failures, seed 10129 | `apps/api/tmp/phase21-final-gate/security-deadline.log`; initial assertion used stale pre-HTTP revision in fixture, fixed by reloading before capture; failed run retained in `rspec-stale-fixture.log` |
| Final backend including security/deadline assertions | Full `rspec` with isolated Redis DB 15, pool 15 and tracing disabled | 554 examples, 0 failures, 4 opt-in pending, seed 33589 | `apps/api/tmp/phase21-final-gate/rspec.log`; 1 minute 2.54 seconds |
| Hosted implementation CI | GitHub Actions [run 37268740679](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37268740679) on SHA `7da69bc1724710548f6db636b8e02392ba1ade1d` | `status=completed`, `conclusion=success`; API, web, Compose jobs all successful | Inspected API RSpec, frontend test/build, Compose Phase 21 smoke and real browser steps; captured run/job metadata under ignored `apps/api/tmp/phase21-final-gate/` |
