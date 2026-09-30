# Phase 11 ExecPlan — Redis projection

Status: IN PROGRESS — primary implementation checkpoint, 2026-09-30.
Current milestone: Live Kafka/Redis integration, failure, replay, crash, concurrency and sabotage campaign in a fresh session.
Completed: Inspected Phase 10 contracts before product edits. Added Redis v1 public snapshot with atomic revision CAS, separate Kafka projection group, explicit eventual public-state endpoint with PostgreSQL fallback, manual PostgreSQL seed script, Compose role and focused tests.
Verified: 20 focused examples/0 failures (seed 41577), Zeitwerk, 6 changed Ruby files linted, Compose syntax and whitespace checks. See Evidence Index.
Remaining: Real broker-to-consumer-to-Redis proof; Redis loss/recovery, Kafka replay, real crash/restart, concurrency and sabotage; then broad regression, runtime checks, ADR/architecture/API/runbook/learning/code-map/journal/progress docs, adversarial review and completion commits.
Known failures/limitations: Initial focused run failed to connect to PostgreSQL because local `.env` was not sourced; rerun with the repository environment passed. No Phase 11 live broker test yet. Phase 10 broker retention, concurrent publication reorder and legacy rows without domain snapshots constrain replay. The new endpoint is explicitly eventual, so a live Redis hit may be stale until a Kafka event arrives; the existing GET remains PostgreSQL-backed.
Relevant files: `apps/api/app/services/{auction_public_projection,kafka_projection_consumer,kafka_event_codec}.rb`, `app/controllers/api/v1/auctions_controller.rb`, `bin/{kafka_projection_consumer,rebuild_auction_projections}`, `spec/integration/redis_projection_spec.rb`, `docker-compose.yml`, `apps/api/Gemfile{,.lock}`; prior public source: `app/models/{auction,outbox_event}.rb`, `app/presenters/api/v1/auction_presenter.rb`.
Relevant ADRs: [ADR-010](../adr/010-transactional-public-outbox.md), [ADR-011](../adr/011-kafka-domain-events.md); Phase 11 ADR to be added for the projection/read policy.
Next-session starting point: Read AGENTS, latest handoff, this plan and Phase 11 spec. Start the new Compose projection consumer and run a real committed auction event through Kafka to Redis, checking API metadata and PostgreSQL truth. Then carry out the live failure/crash/replay/concurrency/sabotage campaign; checkpoint again if substantial final regression/docs remain.

## Primary implementation checkpoint

Redis key `hammerfall:auction-public:v1:<auction_id>` stores schema version, auction ID, public revision, event ID (nil for PostgreSQL seed), occurrence time, Redis write time in milliseconds, source, exact public Kafka v1 data and its digest. The Lua write compares revisions atomically; higher replaces, equal/same digest is duplicate, lower is stale, equal/different digest is a hard conflict that leaves the offset uncommitted. The Kafka consumer validates the Phase 10 envelope, writes Redis, then synchronously commits offset. Redis failure and poison leave the offset uncommitted. The new `GET /api/v1/auctions/:id/public-state` reads this snapshot as an explicitly eventual lean view, exposing source and age. It falls back to PostgreSQL on miss, corruption or Redis error. Existing GET and all commands remain PostgreSQL-backed. The manual rebuild script seeds Redis from current PostgreSQL rows; no scheduled repair was added.

Focused test coverage uses real local PostgreSQL and Redis for public shape/freshness, duplicate/reordered/concurrent revisions, same-revision conflict, stale read vs PostgreSQL, Redis key loss/seed, poison, write outage, simulated post-write/pre-offset crash and read outage. Real Kafka, process crash, full Redis outage, replay and sabotage remain for the next milestone.

The first focused command was run without sourcing `.env` and failed during Rails test schema connection (`PG::ConnectionBad: no password supplied`, no examples run). Sourcing `.env` resolved this; the focused suite then passed. No test was weakened.

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
| Live Redis/Kafka and failure campaign | Pending | Not run | Next milestone |
| Sabotage and broad regression | Pending | Not run | Later milestone |
