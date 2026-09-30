# Current handoff — after Phase 7

Updated: 2026-09-30. Next phase is **Phase 8 — Sidekiq + Redis**, only on an explicit request. Phase 8 has not begun. This is the compact current-state entry point; [progress](../progress.md) holds historical verification detail.

## Working system

- Rails 8 API, PostgreSQL, Next.js/React frontend and an independent Rails closer role run through Compose. Rails is the modular business authority; PostgreSQL owns all durable auction state. No Redis, Sidekiq, outbox, Kafka, external read model, reconciliation worker, observability stack or load-test tooling is installed.
- Users, auctions, accepted bids, private maximum instructions and client idempotency records are implemented. Auction lifecycle is draft → scheduled → active → closed, with cancellation where allowed. The public REST API is versioned under `/api/v1`; actor IDs and lifecycle controls are unauthenticated demonstration endpoints.
- Same-auction writers use a PostgreSQL row lock. Accepted bids have unique auction-local sequences. Private maximum priority and synchronous proxy resolution produce a settled price/leader in one transaction; public output hides unused ceilings, priority and origin. An explicit closer copies leader to winner under the same lock.
- Eligibility uses uncached PostgreSQL `clock_timestamp()` after locking. Soft close adds 90 seconds to the effective end for an accepted logical command in the final 60 seconds. The independent closer rechecks under lock; delayed closure cannot permit late bids.
- Protected HTTP bid/max commands claim an idempotency record before Auction, commit safe terminal response and mutation together, and replay a matching historical outcome without reevaluation. The browser persists one intention per tab before sending and explicitly retries the same key/payload after ambiguity.
- The frontend lists auctions, presents detail/history and bid/max controls, uses integer-cent money, and treats countdowns as estimates. Fresh REST reads determine current price, leader, deadline and winner; accepted command and current leadership are distinct facts.
- Action Cable uses the PostgreSQL adapter for cross-process public invalidations. `public_revision` increments once for a logical public mutation. The only message is `auction.changed.v1` with auction ID and revision, published after the outer commit. The browser refreshes REST on confirmation/reconfirmation or newer hint, coalesces requests and prevents revision regression. Delivery is ephemeral and best-effort.

## Key locations

- Domain/locking/proxy/time: `apps/api/app/models/auction.rb`, `bidding/proxy_resolver.rb`, `auction_clock.rb`, `auction_deadline.rb`; closer in `apps/api/app/services/auction_closer.rb` and `apps/api/bin/auction_closer`.
- Retry: `apps/api/app/services/idempotency/executor.rb`, `idempotent_bidding.rb`, `apps/api/app/models/idempotency_record.rb`; frontend `apps/web/src/lib/intentions.ts` and `apps/web/src/components/auction/session.tsx`.
- API/presentation: `apps/api/app/controllers/api/v1`, `apps/api/app/presenters/api/v1`, `apps/web/src/lib/api`, `apps/web/src/components/auction`.
- Invalidation: `apps/api/app/services/auction_publication.rb`, `apps/api/app/channels/auction_channel.rb`, `apps/web/src/lib/realtime`, and [realtime contract](../realtime.md).
- Schema: `apps/api/db/schema.rb`; adopted decisions: `docs/adr/001`–`008`; exact invariants: [invariants](../invariants.md).

## Verification already completed

Phase 7 final native `bin/ci`: 350 RSpec examples, zero failures, with RuboCop, bundler-audit, Brakeman and Zeitwerk. Frontend recheck: 73 Vitest tests across 10 files, lint, format and typecheck; production build passed. Complete Compose Playwright suite: 7/7, including independent HTTP Rails A and Cable Rails B, missed-hint reconnect, 90-second extension and closer/winner publication. Final container RSpec: 350 examples, zero failures. Compose services were healthy. These are recorded runs, not fresh checks for this documentation migration; GitHub-hosted CI and capacity benchmarks were not run. See [progress, Phase 7](../progress.md#phase-7--real-time-updates).

## Limits and Phase 8 boundary

- Cable can lose a hint after commit or during disconnection; a connected page may stay stale until another recovery trigger. Separate auction/history GETs can observe different commits. A socket is not proof of REST/database health or a command result.
- Demo actor/lifecycle APIs have no authentication/authorization or rate limiting. Private maxima are plaintext to DB operators. `sessionStorage` retry state and the client's one-hour horizon are practical recovery aids, not a permanent guarantee. Idempotency records default to seven-day prune eligibility; physically pruned keys can execute anew.
- PostgreSQL outage stops authority; hot auction locks, listener connections and REST fanout need measurement. No backup/restore, production runbook, capacity, real-money or hosted-CI claim exists.
- Phase 8 should add Sidekiq/Redis application jobs, a notification pipeline and scheduled reconciliation framework, with duplicate/retry/outage behavior and operational recovery. Keep bidding, price, deadline and winner synchronous in PostgreSQL. A queue does not close the commit/enqueue crash gap. Preserve current revision, after-commit public privacy, browser intention and REST recovery contracts. Do not introduce Phase 9 outbox or Phase 10 Kafka early.

Read [Phase 8](../phases/phase-08.md), [async events](../architecture/async-events.md), [realtime/frontend](../architecture/realtime-and-frontend.md), [operations/security](../architecture/operations-and-security.md), and relevant ADRs before implementation. Create a Phase 8 ExecPlan only when the phase is requested.
