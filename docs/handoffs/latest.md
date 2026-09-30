# Current handoff — after Phase 8

Updated: 2026-09-30. **Phase 8 is complete. Phase 9 — Transactional Outbox has not begun** and needs a new explicit request. This is the compact current-state entry point; [progress](../progress.md#phase-8--sidekiq--redis) holds actual run evidence.

## Current system and authority

- Rails/ActiveRecord remains the modular auction authority; PostgreSQL owns users, auctions, accepted bids, private maxima, deadlines, winner, public revision and idempotency outcomes. Same-auction writers serialize on the PostgreSQL row lock. Auction-local bid sequence and private priority settle public price/leader synchronously; explicit close copies leader to winner. Eligibility samples uncached PostgreSQL time after locking; final-60-second accepted commands extend `ends_at` by 90 seconds.
- The versioned REST API and Next.js frontend support listing/detail, bid and private maximum forms, history and recoverable per-tab client intentions. Supplied actor IDs and lifecycle endpoints are unauthenticated demo interfaces. Historical idempotency replay uses the retained original response; fresh GETs supply current state.
- Action Cable still uses PostgreSQL LISTEN/NOTIFY and emits only `{type:"auction.changed.v1",auction_id,revision}`. Public revision advances once in the locked transaction. Browser confirmation/reconnect/higher hints trigger REST reads; Cable never resolves a command or decides price/winner.
- Phase 8 added Redis 7.4, Sidekiq 8.1.7, a job process and separate read-only sweep scheduler. After the outermost commit, `AuctionPublication` enqueues only auction ID/revision. `AuctionChangedJob` reads current PostgreSQL revision and broadcasts the public hint. Duplicate, delayed or reordered jobs cannot mutate auction state. Enqueue failure is logged without changing the committed domain/idempotency outcome. Sidekiq jobs retry up to five times, then enter the Dead set.
- `ReconciliationScheduler` enqueues bounded `ReconciliationSweepJob` pages every 60 seconds by default. It reports PostgreSQL auction price/latest Bid, leader/latest bidder and closed winner/leader drift without repair. No Redis auction projection, outbox, Kafka, domain-event consumer or projection repair exists.

## Key locations

- Auction/proxy/time/closer: `apps/api/app/models/auction.rb`, `bidding/proxy_resolver.rb`, `auction_clock.rb`, `auction_deadline.rb`, `apps/api/app/services/auction_closer.rb`.
- Idempotency: `apps/api/app/services/idempotency/executor.rb`, `idempotent_bidding.rb`, `apps/api/app/models/idempotency_record.rb`; browser intentions in `apps/web/src/lib/intentions.ts` and `apps/web/src/components/auction/session.tsx`.
- Phase 8: `apps/api/app/services/auction_publication.rb`, `apps/api/app/jobs/{auction_changed_job,reconciliation_sweep_job}.rb`, `apps/api/app/services/reconciliation_scheduler.rb`, `apps/api/bin/reconciliation_scheduler`, `apps/api/config/sidekiq.yml`, `docker-compose.yml`; [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md), [runbook](../runbooks/sidekiq-redis.md).
- Public contract: `apps/api/app/channels/auction_channel.rb`, `apps/web/src/lib/realtime`, [realtime](../realtime.md), [invariants](../invariants.md). Schema: `apps/api/db/schema.rb` (no Phase 8 migration).

## Verified evidence

Final full container RSpec: **359 examples, zero failures**. Native `scripts/check` before the final two spec additions: 357 backend examples plus 73 frontend tests, lint, Brakeman, eager loading, typecheck and production build passed; the added specs passed in the later full container run. Bundler audit found no vulnerabilities. Compose built/started all seven roles. Real-API Playwright: **7/7**, including proxy, reconnect, deadline extension and closer publication. API A/3001 to independent Cable B/3002 proof passed through Sidekiq (revision 2 → 3 → REST 3). Worker-stop backlog (0 → 3 → 0), Redis-stop bid/replay, API restart without Redis, scheduler fail/recovery and real RetrySet placement were observed. Three temporary sabotage overrides each made its targeted test fail; final normal tests passed. Hosted CI and capacity benchmarks were not run. Details and fixture IDs are in [progress](../progress.md#phase-8--sidekiq--redis).

## Limits and Phase 9 gate

- Commit followed by crash before enqueue, failed enqueue, Redis loss, exhausted retries or Cable failure can lose a hint; Sidekiq/AOF is not an outbox. Connected clients can remain stale until another REST recovery trigger. Sidekiq queue drain is not delivery proof. Separate auction/history GETs are not one snapshot.
- The read-only sweep has no repair authority. It can repeat drift logs; Redis persistence/HA, Dead-set ownership, job and PostgreSQL connection capacity, backups and production monitoring remain unresolved. There is no authentication, authorization, rate limiting, real-money readiness or performance claim.
- Phase 9 should design an OutboxEvent write inside the existing authoritative transaction, a publisher/retry/order policy and failure tests **without changing bid, deadline, winner or idempotency semantics**. Read [Phase 9](../phases/phase-09.md), [async architecture](../architecture/async-events.md), [ADR-009](../adr/009-sidekiq-public-notifications-and-sweeps.md), and only the relevant auction/idempotency/transaction code. Create a Phase 9 ExecPlan before implementation. Do not introduce Kafka (Phase 10) early.
