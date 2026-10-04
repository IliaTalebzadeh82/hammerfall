# Phase 21 ExecPlan — Marketplace trust and auction policy

Status: In progress; Session 2 hidden reserve milestone complete, checkpoint ready.
Current milestone: Resume with rapid closing in a fresh session.
Completed: Session 1 research/stepped increments; [Session 2 report](../marketplace/phase-21-session-2.md); private nullable reserve with draft freeze, locked manual/proxy/close semantics, SQL winner constraint, v2 public snapshot/event migration with v1 replay support, v2 Redis projection/reconciliation, public frontend status and privacy tests.
Verified: Test PostgreSQL migrate/rollback/reapply; 311 affected backend examples/0 failures/2 opt-in pending on isolated Redis DB 15; 5 independent reserve maximum race seeds/0 failures; 33 frontend tests/0 failures, typecheck/lint/build; 20 Ruby files RuboCop clean; Zeitwerk clean. See Evidence Index.
Remaining: Implement rapid closing from ADR-020, combined reserve/rapid cases, real multi-instance/Compose/Kafka/Redis delivery proof, full Phase 21 regression/browser/adversarial gate, hosted CI and phase completion. Do not start Phase 22.
Known failures/limitations: Session 1 shared Redis DB 0 contamination resolved by DB 15 isolation. Stepped `minimum_increment` create input remains required but ignored by pricing. Active reserve lowering/removal, seller management UI, payment and post-auction offers are deliberately deferred. No live broker/multi-instance or full Phase 21 gate yet.
Relevant files: `apps/api/app/models/auction.rb`, `apps/api/app/models/bidding/{bid_increment_policy,proxy_resolver}.rb`, `apps/api/app/models/public_auction_snapshot.rb`, `apps/api/app/services/{kafka_event_codec,auction_public_projection,auction_projection_reconciler}.rb`, migration `20261004020000`, frontend auction components and reserve/integration specs.
Relevant ADRs: [ADR-003](../adr/003-auction-concurrency-control.md), [ADR-004](../adr/004-proxy-bidding.md), [ADR-005](../adr/005-auction-deadlines-and-soft-close.md), [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-018](../adr/018-stepped-bid-increments.md), [ADR-019](../adr/019-hidden-reserve-policy.md), [ADR-020](../adr/020-auction-closing-policies.md).
Next-session starting point: Read this plan, [latest handoff](../handoffs/latest.md), [Session 2 report](../marketplace/phase-21-session-2.md) and ADR-020. Begin rapid closing only, then combined reserve/rapid verification and remaining live/final Phase 21 gates. Do not start Phase 22.

## Decisions

- Session 2 async contract: INTRODUCE v2. The v1 Kafka/Redis validator requires exact public fields and v1 winner semantics, so new domain snapshots use `.v2` types and `schema_version=2`. Consumers still decode retained v1 events as historical no-reserve state and normalize to `reserve_status=none`; Redis uses a v2 key, with PostgreSQL seed/reconciliation restoring current state. Cable remains an unchanged `auction.changed.v1` invalidation. The Kafka topic and consumer groups retain their offsets/replay order. Deploy migration/readers and drain old writers/consumers before enabling reserve writers.
- ADOPT price band increments, private reserve, and a rapid closing policy. Each has a direct locked-state or deadline invariant and first-party public evidence. Increment was implemented in Session 1 and reserve in Session 2; rapid closing remains pending.
- SATISFIED BY PHASE 20: seller self-bid rejection, after the auction lock and authenticated actor resolution.
- DEFER account/country/category restrictions and bid reservations: meaningful versions require signals, payment holds, and rules absent from this case study.
- REJECT the lightweight bidding-panel experiment for Phase 21: it does not strengthen proof of auction policy and would require separate consent, retention and analytics semantics.
- Existing auctions retain their fixed increment. A new opt-in stepped schedule is a Hammerfall approximation of the current published Catawiki table; their help article warns that some lots differ due to experiments. Reserve and rapid closing designs will also be explicit Hammerfall approximations.

## Evidence Index

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
