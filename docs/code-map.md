# Code map

Paths below are relative to the repository root. Phase 5 resolves client key ownership before the PostgreSQL auction row lock.
Phase 9 adds a transactional outbox for public invalidations; Kafka domain events do not exist yet.

## Creating an auction

- HTTP route: `apps/api/config/routes.rb`, POST `/api/v1/auctions`.
- Shape/allowlist: `app/controllers/api/v1/auctions_controller.rb#auction_params`
  and `app/controllers/api/v1/base_controller.rb#resource_params` (under apps/api).
- Initialization/validation: `apps/api/app/models/auction.rb#create_draft!`.
- Money validation: `apps/api/app/validators/minor_units_validator.rb`.
- Persistence/constraints: `apps/api/db/migrate/20260924000000_create_core_auction_domain.rb`.
- Response: `apps/api/app/presenters/api/v1/auction_presenter.rb`.
- Tests: `apps/api/spec/models/auction_spec.rb`, `spec/requests/auctions_spec.rb`.

## Transitioning an auction

- HTTP entry: `apps/api/app/controllers/api/v1/auctions_controller.rb`:
  schedule, activate, close, cancel.
- Domain entry: `apps/api/app/models/auction.rb` public bang methods.
- Transaction, transition table, preconditions, winner selection:
  `transition_to!`, `check_transition_preconditions!`, `close!` in that model.
  The transaction starts with the same `reload(lock: true)` used by bidding.
- Guard against bypass: `managed_changes` validation (no mutation callbacks).
- Error translation: `apps/api/app/models/domain_error.rb` and API BaseController.
- Tests: full edge matrix and boundary-time cases in `spec/models/auction_spec.rb`;
  HTTP lifecycle cases in `spec/requests/auctions_spec.rb`.

## Placing a bid

- HTTP entry: `apps/api/app/controllers/api/v1/bids_controller.rb#create`.
- Actor: IdempotentBidding finds User from supplied bidder_id; no authentication yet.
- Protected HTTP wrapper: Idempotency::Executor resolves a required client key before
  the domain path below; completed retries bypass it entirely.
- Domain and transaction: `apps/api/app/models/auction.rb#place_bid!`,
  `transaction(requires_new: true)` (a savepoint when nested).
- Lock and fresh state: `reload(lock: true)` issues SELECT FOR UPDATE before any
  eligibility decision. Time is sampled after waiting.
- Validation: active/window/minimum checks there; participants and money in
  `apps/api/app/models/bid.rb` and `app/validators/minor_units_validator.rb`.
- Ordering: compute MAX(sequence)+1 while locked; Bid validates a positive integer.
- Writes: ProxyResolver inserts accepted/generated Bids and assigns price/leader;
  Auction persists them with any extension inside that transaction.
- COMMIT: return the Bid only when the transaction completes; a nested caller must
  still commit its outer transaction before reporting durable success.
- Schema defense: `20260924010000_add_authoritative_bid_sequence.rb`, positive
  NOT NULL sequence and unique (auction_id, sequence); index supports ordered history.
- HTTP response after commit: BidsController renders 201 using
  `apps/api/app/presenters/api/v1/bid_presenter.rb` (includes sequence).
  DomainError becomes 422 in BaseController, with the fresh rejection price/minimum.
- Tests: `apps/api/spec/models/bid_spec.rb` (including failed-price-write rollback),
  `spec/requests/bids_spec.rb`, `spec/integration/domain_constraints_spec.rb`.
- Concurrency evidence: `apps/api/spec/integration/concurrent_bidding_spec.rb`: stale
  waiter, many bidders, same amount, real UPDATE failure, lifecycle/time changes,
  waiting close, and independent auctions; separate committed database sessions.

## Listing bid history

- HTTP entry: `apps/api/app/controllers/api/v1/bids_controller.rb#index`.
- Scoped relation: `find_auction.bids`.
- Ordering/page bounds: API BaseController `render_collection(order_key: :sequence)`,
  sequence ascending, limit+1 fetch, optional after_sequence; IDs remain identity.
- Public representation: BidPresenter.
- Tests: pagination and auction isolation in `spec/requests/bids_spec.rb`.

## Identity and demo

- User: `apps/api/app/models/user.rb`.
- HTTP: `apps/api/app/controllers/api/v1/users_controller.rb`.
- Seeds: `apps/api/db/seeds.rb`; empty development domains only.
- Tests: `spec/models/user_spec.rb`, `spec/requests/users_spec.rb`,
  `spec/integration/seeds_spec.rb` under apps/api.

## Foundation and verification

- Liveness: `apps/api/config/routes.rb` → built-in Rails health controller `/up`;
  `apps/api/spec/requests/health_spec.rb`.
- Database setup: `apps/api/config/database.yml`; connectivity coverage in
  `apps/api/spec/integration/database_spec.rb`.
- Web entry: `apps/web/src/app/layout.tsx`; `/` redirects to `/auctions`. See the Phase 6 maps below.
- Compose: `docker-compose.yml` and `infrastructure/` development Dockerfiles.
- Checks: `scripts/check`, `apps/api/config/ci.rb`, `.github/workflows/ci.yml`.
- Executable HTTP demonstration: `scripts/smoke-api` and
  `scripts/smoke-concurrent-bids`; create labelled demo records.

## Phase 3: first maximum and maximum increase

- HTTP: `apps/api/config/routes.rb` PUT maximum-bid member route.
- Input/actor: `apps/api/app/controllers/api/v1/maximum_bids_controller.rb#update`.
- Transaction + auction lock + eligibility: `apps/api/app/models/auction.rb#set_maximum!`,
  transaction(requires_new: true), reload(lock: true), validate_bidding_window!.
- Private state: `apps/api/app/models/maximum_bid.rb`; command compares prior amount,
  rejects reductions, returns unchanged on equal input, assigns fresh priority and
  saves explicitly. Parent association does not implicitly save private state.
- Algorithm: `apps/api/app/models/bidding/proxy_resolver.rb#maximum`/`#resolve`.
  A first bidder gets starting_price. Leader protection updates emit nothing.
- Generated rows: #emit increments auction-local visible sequence and saves Bid
  with internal origin; #finish assigns leader; Auction#persist_bidding_action! saves price/leader/deadline.
- COMMIT then HTTP: MaximumBidsController acknowledges auction_id/bidder_id/accepted,
  without any maximum/priority/origin serialization.

## Phase 3: manual versus automatic, two maxima, and ties

- Manual HTTP entry remains BidsController#create → Auction#place_bid!.
- After row lock and fresh manual minimum validation, ProxyResolver#manual calls
  #resolve. Maximum commands reach the same resolver via #maximum.
- #resolve reads the incumbent's current instruction and compares ceilings; equal
  ceilings compare explicit priority. Loser's ceiling precedes winner's minimal
  offer. A winning manual offer retains its exact submitted amount.
- #emit writes up to two visible rows, including equal-price tie rows; #finish assigns
  the selected leader; Auction persists price/leader/end; all changes share the entry-point transaction.
- Manual API returns its accepted Bid after complete resolution, even when outbid.
  History lists all committed generated rows in sequence order with origin omitted.
- Existing close! copies current_leader_id to winner_id under the same lock.
- Schema/backfill: `20260924020000_add_maximum_bidding.rb`; SQL constraints protect
  current instruction uniqueness, private priority, origin and leader references.
- Privacy: `config/initializers/filter_parameter_logging.rb` plus explicit presenters
  and MaximumBidsController's acknowledgement; no public private-state read path.
- Tests: `spec/models/maximum_bid_spec.rb`,
  `spec/integration/concurrent_maximum_bidding_spec.rb`,
  `spec/integration/maximum_bid_constraints_spec.rb`,
  `spec/requests/maximum_bids_spec.rb` under apps/api. Both concurrency groups use
  `spec/support/committed_auction_context.rb` for owned committed data/session helpers.
- Live demonstration: `scripts/smoke-proxy-bidding` exercises four concrete scenarios.

## Phase 4: late manual bid, maximum increase and soft close

- HTTP remains `app/controllers/api/v1/bids_controller.rb#create` or
  `maximum_bids_controller.rb#update` under `apps/api`.
- `apps/api/app/models/auction.rb#place_bid!` / `#set_maximum!`: savepoint,
  `reload(lock: true)`, **one** `AuctionClock.now`, eligibility and full settlement.
- `apps/api/app/models/auction_clock.rb#now`: uncached DB clock_timestamp() using
  the currently checked-out connection; no permanent lease or application time.
- `apps/api/app/models/auction_deadline.rb`: `due?` and `extended_end` pure arithmetic.
- `Auction#persist_bidding_action!`: once per accepted external commitment, +90 to
  effective end within the final 60, then save price/leader/end together. Same-max
  early return never reaches this method. Protection-only increases do reach it.
- `Bidding::ProxyResolver#finish` now assigns the leader; the Auction command owns
  the final save, including extension. Internal `#emit` calls never extend.
- Tests: `apps/api/spec/models/auction_deadline_spec.rb` exact boundaries;
  `models/soft_close_spec.rb` zero/two-row, rejected/no-op,
  frozen fields and query-cache behavior; `integration/concurrent_closing_spec.rb`
  real SQL rollback of the calculated extension, including private state.

- `apps/api/spec/integration/repeated_soft_close_spec.rb`: two successive real
  windows with actual separate commits, verified from independent sessions.

## Phase 4: autonomous close, duplicate/stale closer and winner finalization

- Entrypoint `apps/api/bin/auction_closer`: same Rails environment, validated role
  settings, stdout logging, signal stop flag, --once mode, role PG timeouts.
- `apps/api/app/services/auction_closer.rb#candidate_ids`: bounded ordered active/due
  ID discovery against a sampled DB cutoff; `#run_once` invokes domain close;
  `#run` polls, releases connections, logs/retries known transient failures.
- `apps/api/app/models/auction.rb#close!`: lock/reload, DB decision time, closed or
  not-due no-op, due active -> closed/winner=current_leader/closed_at in one save.
- `apps/api/app/controllers/api/v1/auctions_controller.rb#close` uses that same method;
  early close returns the unchanged active representation. No force-close operation.
- Schema: `apps/api/db/migrate/20260924030000_add_auction_deadlines.rb` backfills
  original/closed times, checks timestamp/winner shape and indexes active ends_at,id.
- Public times/leader/winner: `app/presenters/api/v1/auction_presenter.rb` under apps/api.
- Bid-vs-close / max-vs-close races, duplicate eight-session contenders and stale
  candidate discovery are in `apps/api/spec/integration/concurrent_closing_spec.rb`.
  `integration/deadline_constraints_spec.rb` proves SQL defenses;
  `models/auction_closer_spec.rb` covers bounded discovery/configuration/shutdown.
- Process role/image: `docker-compose.yml` auction-closer reuses hammerfall-api.
- Live HTTP and independent closing processes: `scripts/smoke-closing` (development
  only; stop ordinary closer for controlled delayed/stale scenarios).

## Phase 4: lazy expiry detection from bidding

`Auction#validate_bidding_window!` uses the captured post-lock clock and raises
auction_ended for expired active rows. **Detection is lazy; finalization is not.**
Rejected bids/maxima persist no state; `close!` owns all finalization. The delayed
scenario in concurrent_closing_spec.rb and scripts/smoke-closing proves rejection
with active status followed by eventual close. requests/bids_spec.rb verifies the
public error. No duplicated winner logic or exception-after-commit protocol exists.

## Phase 5: idempotent manual/proxy bids and maximum increases

- Header/shape/IDs: `apps/api/app/controllers/api/v1/bids_controller.rb#create` and
  `maximum_bids_controller.rb#update`; `Idempotency::Executor.validate_key!` checks
  bounded ASCII key format. BaseController#render_idempotent handles replay marker.
- Application operation: `apps/api/app/services/idempotent_bidding.rb.call` identifies
  User, selects typed amount argument and calls Executor before Auction lookup.
- Canonical fingerprint, ownership and transaction:
  `apps/api/app/services/idempotency/executor.rb.call`. Fixed v1 semantic JSON is
  SHA-256 hashed; raw client key is represented by SHA-256 key_digest.
- Claim: IdempotencyRecord.insert_all with unique_by index_idempotency_records_on_scope
  emits INSERT ON CONFLICT DO NOTHING RETURNING id. New processing ownership and
  terminal response share the outer transaction with all domain writes.
- Newly owned: IdempotentBidding block loads Auction, calls #place_bid! or #set_maximum!,
  which lock/reload/time-check/settle under their existing requires_new savepoint.
  ProxyResolver and persist_bidding_action! retain Phase 3/4 behavior.
- Public result: BidPresenter or explicit maximum acknowledgment; Executor records
  terminal status/public JSON, reloads normalized JSONB, then commits before HTTP.

## Phase 5: duplicate, conflict, rollback and retry

- Existing claim: Executor compares fingerprint first. Matching completed outcome
  returns Outcome(replayed: true) without yielding to IdempotentBidding's Auction
  block. Different payload returns 409 and never replaces the old snapshot.
- DomainError/RecordInvalid/RecordNotFound inside execution become stored 422/404
  outcomes after domain savepoint rollback. Other exceptions and terminal-write
  failures roll back the whole outer transaction, including ownership.
- SQL schema: `apps/api/db/migrate/20260925000000_create_idempotency_records.rb`:
  composite uniqueness, actor FK, digest/operation/outcome/retention constraints.
- Record and prune: `apps/api/app/models/idempotency_record.rb` guards normal terminal
  updates; #prune_expired! locks a bounded completed/expired batch with SKIP LOCKED.
  `apps/api/lib/tasks/idempotency.rake` exposes bin/rails idempotency:prune.
- Privacy filters: `apps/api/config/initializers/filter_parameter_logging.rb`.
- Tests to study: `apps/api/spec/requests/idempotency_spec.rb` exact response/marker,
  canonicalization, key scope, conflicts, historical replay and log/database privacy;
  `integration/concurrent_idempotency_spec.rb` ten duplicates, conflicting payloads,
  post-close replay while Auction is locked, actual snapshot SQL failure and rollback
  takeover; `models/idempotency_record_spec.rb` unexpected failure and prune/reuse;
  `integration/idempotency_constraints_spec.rb` real SQL defenses.
- Live executable: `scripts/smoke-idempotency`, development-only, requires two API URLs
  and retains labelled rows. Existing smoke scripts issue fresh keys per intention.

## Phase 6: browser routes and public reads

All paths in this section begin under `apps/web` unless otherwise noted.

- `/`: `src/app/page.tsx` redirects to `/auctions`.
- List: `src/app/auctions/page.tsx` → `components/auction/auction-list.tsx` →
  `lib/api/client.ts#getAuctions`; ID cursor and Load more, explicit/focus refresh.
- Detail: `src/app/auctions/[id]/page.tsx` awaits and validates params →
  `components/auction/auction-detail.tsx`; getAuction + getBids refresh together.
- API transport: `next.config.ts` rewrite and API_ORIGIN; no API route handlers.
  `lib/api/types.ts` contains public-only models; client.ts guards runtime shapes,
  bounded numeric values, metadata, pagination and error envelopes.
- History: `presentation.tsx#BidHistory` renders explicit public fields by sequence;
  detail's moreHistory follows next_after_sequence. New refresh resets pagination.
- Read races: detail/list abort prior reads; detail generation also guards late
  history pagination. `reads.test.tsx` proves a late older GET cannot replace new state.

## Phase 6: demo actor and manual/maximum commands

- Shell/provider: `src/app/layout.tsx` installs `AuctionSession`/`ApplicationShell`
  from `components/auction/session.tsx`. User pages come from getUsers; selected ID
  is stored as hammerfall.actor in localStorage, explicitly not authentication.
- Forms: `components/auction/bidding-panel.tsx#AmountForm` validates strings with
  `lib/money.ts#parseEuroInputToCents`, then calls session.submit. Binding maximum
  copy is inline; no max cancellation/read endpoint or inferred protection display.
- Intention: session.submit generates crypto.randomUUID only on a new submission.
  execute persists the immutable intention before calling client.ts#sendCommand.
- Manual: sendCommand POSTs bid {bidder_id,amount}; maximum: PUTs maximum_bid
  {bidder_id,maximum_amount}. Both send Idempotency-Key and preserve response metadata.
- Pending/ambiguous: the ref prevents same-turn duplicate clicks; one saved command
  blocks both forms/actor changes. `lib/intentions.ts` validates and restores session
  data; only exact allowlisted values become the retry payload.
- Safe retry: session.retry checks the one-hour horizon and reuses the same command.
  ApplicationShell offers recovery across routes and inline two-step abandonment.
- Replay/terminal result: sendCommand recognizes Idempotency-Replayed; session stores
  an outcome revision, removes pending storage; detail reacts by refreshing auction
  AND history. Its state comes from GET, never the returned command price.
- Stale rejection: client.ts#errorMessage maps stable codes and safe historical
  price/minimum details. The same terminal refresh runs on rejection, including 409.
- Privacy: public types omit private fields, history has explicit cells, changing
  actor remounts/clears form input, and pending maxima never enter logs/URLs.

## Phase 6: countdown, layout and verification

- `presentation.tsx#AuctionTiming`: isolated local ticks, offset from X-Server-Time,
  one expiration callback per ends_at, Checking status until Rails says otherwise.
- Header source: `apps/api/app/controllers/api/v1/base_controller.rb#set_presentation_time`;
  response metadata only, covered by `spec/requests/presentation_time_spec.rb`.
- Layout: `src/app/globals.css`; shadcn Button/Badge/Input/Label/Alert/Skeleton under
  `src/components/ui`. Semantic labels, error/live regions and public table headings.
- Unit/component tests: lib/money.test.ts, lib/api/client.test.ts,
  lib/intentions.test.ts; components/auction/{commands,reads,presentation}.test.tsx.
- Real API browser tests: `e2e/auctions.spec.ts`, `playwright.config.ts`; real browsing,
  actor selection, manual/max, stale rejection, commit-then-drop-response/reload/retry,
  countdown/closure and 390/768/1440 screenshots with long titles/large amounts.
- Commands: `npm test`, lint, format:check, typecheck, build, test:e2e. CI's Compose
  job starts real Rails/PostgreSQL/closer and runs the browser scenarios.

## Phase 7 implementation map

- `apps/api/db/migrate/20260929000000_add_public_auction_revision.rb`: revision schema and guarded downgrade.
- `apps/api/app/models/auction.rb`: locked public-save/revision boundary.
- `apps/api/app/services/auction_publication.rb`: outermost-commit publication and transport failure isolation.
- `apps/api/app/channels/auction_channel.rb`, `config/cable.yml`, `config/application.rb`: public subscription, PostgreSQL adapter, origins/workers.
- `apps/api/spec/integration/public_revision_spec.rb`: actual commits, rollback/savepoints, independent visibility, privacy, replay and concurrent closure.
- `apps/api/spec/channels/auction_channel_spec.rb`: stream selection and invalid subscriptions.
- `apps/web/src/lib/realtime/auction-subscription.ts`: owned official Cable consumer and envelope validation.
- `apps/web/src/lib/realtime/refresh-coordinator.ts`: revision ordering, coalescing, bounded recovery and cleanup.
- `apps/web/src/components/auction/realtime.test.tsx`: connection/REST separation and pending-command preservation.
- `apps/web/e2e/realtime.spec.ts`: real two-client proxy/extension/closure/reconnect.
- `apps/web/scripts/verify-realtime.mjs`: independent API/Cable process proof and origin checks.
- `docs/realtime.md`, `docs/adr/008-realtime-auction-invalidations.md`: protocol, rationale and limitations.

## Phase 8 implementation map

- `apps/api/app/models/auction.rb#persist_public_change!` increments revision in
  the existing locked transaction; `AuctionPublication.after_commit` transfers
  the callback to the outermost commit and then enqueues a scalar ID/revision.
- `apps/api/app/jobs/auction_changed_job.rb` reads current PostgreSQL revision
  and calls `AuctionPublication.broadcast` with the unchanged public-only payload;
  the existing `AuctionChannel` and browser REST refresh coordinator remain.
- `apps/api/app/jobs/reconciliation_sweep_job.rb` scans bounded SQL snapshots,
  compares latest Bid to auction price/leader and closed winner, logs drift only,
  and chains the next cursor. `ReconciliationScheduler` and
  `bin/reconciliation_scheduler` periodically enqueue the first batch.
- `docker-compose.yml`, `config/sidekiq.yml`, `.env.example` and CI configure
  Redis, the worker, scheduler and two queues. API startup is Redis-independent.
- `apps/api/spec/jobs`, `spec/integration/public_revision_spec.rb` test jobs,
  commit/enqueue isolation, privacy, duplicates, ordering and read-only drift.
  `apps/web/scripts/verify-realtime.mjs` and Playwright prove the actual
  worker-to-Cable-to-REST flow across processes.
- `docs/adr/009-sidekiq-public-notifications-and-sweeps.md` and
  `docs/runbooks/sidekiq-redis.md` explain guarantees and operational recovery.

## Phase 9 implementation map

- `Auction#persist_public_change!` inserts `OutboxEvent` after saving each public
  revision and before its transaction/savepoint exits. `Idempotency::Executor`
  encloses the domain command and stored outcome; replay never re-enters the write.
- The migration and `OutboxEvent` model define the public-only version 1 envelope,
  unique auction/revision identity, due index, retry and enqueue acknowledgment.
- `OutboxPublisher` and `bin/outbox_publisher` form the independent poller. Each
  due row is claimed with `FOR UPDATE SKIP LOCKED`; `docker-compose.yml` starts
  the publisher role. The Sidekiq client initializer bounds Redis network waits.
- `AuctionChangedJob` reads current PostgreSQL revision and broadcasts the
  unchanged Cable hint. Duplicate/reordered jobs cannot decide auction state.
- `spec/integration/transactional_outbox_spec.rb` covers atomicity, replay,
  privacy, retry, duplicate enqueue and concurrent row claims. The Phase 9
  ExecPlan records live crash and Redis-outage evidence.
- [ADR-010](adr/010-transactional-public-outbox.md), [event model](event-model.md),
  [failure model](failure-model.md) and [runbook](runbooks/sidekiq-redis.md)
  describe the contract and recovery procedure.
