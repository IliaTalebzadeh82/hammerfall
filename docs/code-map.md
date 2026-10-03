# Code map

## Phase 20 Session 2 security path

`apps/api/lib/request_body_limit.rb` bounds API input before Rails parameter
parsing. `app/services/rate_limit_store.rb` supplies shared Redis counters to
session, bid, maximum, lifecycle and Cable admission; its failure policy is
endpoint-specific. `app/services/security_events.rb` emits bounded taxonomy
through the existing observability allowlists. `app/services/idempotency/keyring.rb`
loads the shared HMAC keyring; `app/services/idempotency/executor.rb` takes a
PostgreSQL advisory lock before legacy/current/previous digest lookup and claim.
`20261003010000_version_idempotency_digests.rb` versions retained rows. The
browser client in `apps/web/src/lib/api/client.ts` treats 413/429 as definite
pre-command rejection. See [ADR-017](adr/017-versioned-keyed-idempotency-digests.md)
and the [Session 2 report](security/phase-20-session-2.md).

## Phase 20 Session 1 identity path

`POST /api/v1/session` verifies a bcrypt password, creates a PostgreSQL
`UserSession` and sets an encrypted HttpOnly cookie. `GET /session` supplies
the current actor and CSRF token; `DELETE /session` revokes the row. See
`apps/api/app/controllers/api/v1/sessions_controller.rb`,
`app/models/user_session.rb` and `app/models/user.rb`. Protected controllers
use `BaseController#require_actor!` and `#verify_authenticated_csrf`, then
`AuctionPolicy` for ownership/operator capability. Bid controllers pass the
authenticated ID to the unchanged `IdempotentBidding` executor; `Auction`
rejects seller self-bids after its PostgreSQL row lock. Cable resolves the
same session row at handshake and checks it again at subscription. The web
session component handles login, logout and reauthentication before same-key
retry. Older demo-actor descriptions below are historical Phase 6/7 maps.

Paths below are relative to the repository root. Phase 5 resolves client key ownership before the PostgreSQL auction row lock.
Phase 10 extends the transactional public outbox with Kafka domain events and an audit consumer.

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
- Actor: `BaseController` authenticates the session, and the bid controller
  passes its user ID to `IdempotentBidding`; supplied `bidder_id` is rejected.
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
  SHA-256 hashed; new raw client keys use a versioned HMAC digest. Retained
  legacy SHA-256 key digests remain readable for same-key replay.
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
  login, manual/max, stale rejection, commit-then-drop-response/re-login/retry,
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
  `PublicAuctionSnapshot` checks shared Kafka/Redis public semantics; migration
  `20261001012000_constrain_original_auction_window.rb` also enforces the
  original deadline after start on authoritative auction rows.
- `OutboxPublisher` and `bin/outbox_publisher` form the independent poller. Each
  due row is claimed with `FOR UPDATE SKIP LOCKED`; `docker-compose.yml` starts
  the publisher role. The Sidekiq client initializer bounds Redis network waits.
  The row transaction spans enqueue; see ADR-010 for the Phase 12.5 retention
  decision and its connection/lock cost.
- `AuctionChangedJob` reads current PostgreSQL revision and broadcasts the
  unchanged Cable hint. Duplicate/reordered jobs cannot decide auction state.
- `spec/integration/transactional_outbox_spec.rb` covers atomicity, replay,
  privacy, retry, duplicate enqueue and concurrent row claims. The Phase 9
  ExecPlan records live crash and Redis-outage evidence.
- [ADR-010](adr/010-transactional-public-outbox.md), [event model](event-model.md),
  [failure model](failure-model.md) and [runbook](runbooks/sidekiq-redis.md)
  describe the contract and recovery procedure.

## Phase 10 implementation map

- `Auction#persist_public_change!` classifies the public delta and stores a
  public snapshot on the same `OutboxEvent` row as the Phase 9 invalidation.
  Migration `20260930000001_add_kafka_to_outbox.rb` adds independent Kafka retry
  and acknowledgment columns; migration `20260930000002_add_kafka_receipt_digest.rb`
  records consumer identity integrity. Historical rows are not synthesized.
- `KafkaOutboxPublisher` and `bin/kafka_outbox_publisher` claim committed rows,
  send with the auction ID partition key, wait for broker delivery and only then
  acknowledge in PostgreSQL. `KafkaEventCodec` validates the exact public v1
  shape. `docker-compose.yml` runs the broker, topic initializer and publisher.
  This transaction locks the same outbox row as the Sidekiq path during I/O;
  delivery state remains independent. See ADR-011 and the Phase 12.5 ExecPlan.
- `KafkaAuditConsumer` and `bin/kafka_audit_consumer` form the initial group.
  `ConsumedKafkaEvent` and `KafkaAuditEntry` commit receipt and audit effect
  together; offset commit follows. The group stops on poison and has no
  automatic restart policy. No projection or auction decision reads these tables.
- `spec/integration/kafka_outbox_spec.rb` covers atomicity, privacy, retry,
  duplicate, offset and concurrent claim behavior. `scripts/smoke-kafka`
  exercises Compose end to end; the Phase 10 ExecPlan records real outage,
  crash, replay, poison, sabotage and regression evidence.
- [ADR-011](adr/011-kafka-domain-events.md), [event model](event-model.md)
and [Kafka runbook](runbooks/kafka.md) define the wire and recovery contract.

## Phase 11 implementation map

- `AuctionPublicProjection` owns the versioned Redis key, public snapshot
  validation/digest, atomic revision compare, read and PostgreSQL seed.
- `PublicAuctionSnapshot` centralizes public field semantics for Kafka decoding
  and projection validation without synthesizing a Kafka envelope.
- `KafkaProjectionConsumer` and `bin/kafka_projection_consumer` own the separate
  group, v1 envelope validation, Redis effect and subsequent offset commit.
  `docker-compose.yml` starts the consumer separately from the audit group.
- `AuctionsController#public_state` and `config/routes.rb` expose the explicit
  eventual read; normal `#show` and every command remain PostgreSQL-backed.
- `bin/rebuild_auction_projections` iterates authoritative auction rows to
  restore disposable keys. `spec/integration/redis_projection_spec.rb` covers
  revisions, retries, outage, fallback, recovery and public-only content.
- [ADR-012](adr/012-redis-public-projection.md), [projection architecture](architecture/projections-and-reconciliation.md)
  and [runbook](runbooks/redis-projection.md) explain the consistency boundary.

## Phase 12 implementation map

- `AuctionProjectionReconciler#check` reads PostgreSQL public revision and
  presenter fields independently of Redis. Missing/lower-revision keys call
  `AuctionPublicProjection#seed`, which uses the existing atomic Redis script;
  conflicts, ahead keys and corrupt envelopes produce operator-review logs.
- `AuctionProjectionReconciliationJob` scans at most 100 auction IDs per page
  under a fixed ceiling, emits per-batch count logs and chains the cursor.
  `ReconciliationSweepJob` remains a separate read-only PostgreSQL check.
- `ReconciliationScheduler` claims one lease per scan type before enqueue.
  `ReconciliationLease` and `reconciliation_leases` use PostgreSQL clock,
  owner token and cursor fencing so retries and multiple schedulers cannot
  fork scheduled chains. Expired ownership restarts from ID zero; manual
  tokenless jobs are independent.
- `auction_projection_reconciliation_spec.rb`,
  `auction_projection_reconciliation_live_spec.rb`,
  `reconciliation_lease_spec.rb` and `reconciliation_sweep_job_spec.rb` cover
  drift, Kafka races, concurrency, bounded pages and crash recovery. The
  [ExecPlan](plans/phase-12-execplan.md) indexes live outage/sabotage evidence;
  [ADR-013](adr/013-bounded-reconciliation-scan-ownership.md) and the
  [runbook](runbooks/projection-reconciliation.md) define operations.

## Phase 13 observability map

- `lib/observability.rb` configures bounded OTLP tracing/metrics, normalizes
  metric dimensions and span attributes, and writes correlated JSON boundary
  logs. `config/initializers/observability.rb` activates it only when
  `OTEL_ENABLED=true`; initialization errors disable telemetry.
- `lib/observability/http_middleware.rb` extracts W3C trace context and uses
  fixed HTTP route templates. Bid controllers count requests and terminal
  outcomes. `Auction` measures row-lock acquisition separately from decision,
  proxy, save and outbox persistence spans.
- `infrastructure/observability/` holds Collector, Prometheus, Tempo and
  Grafana provisioning. `docker-compose.yml` places them in an optional
  profile without adding application health dependencies.
- `spec/lib/observability_spec.rb` checks bounded labels, private-field
  exclusion and exactly-once domain-block execution during telemetry errors.
  The [Phase 13 ExecPlan](plans/phase-13-execplan.md) indexes live evidence
  and tracks remaining phase completion gates.
- `OutboxEvent#trace_carrier` and its trace columns persist only bounded W3C
  metadata. `lib/observability/sidekiq_middleware.rb` handles producer/worker
  context without changing public job arguments; Kafka publisher/consumers use
  `rdkafka` headers without changing the v1 business envelope.
- The two publishers emit attempts, retries, failures, duration and global
  backlog/age gauges. Kafka consumers emit bounded result counters and sampled
  broker lag after offset commits. Projection/reconciliation emit actual
  cumulative counters; their batch logs now use `_batch` names.
- `infrastructure/observability/grafana/dashboards/hammerfall-operations.json`
  covers auction health, delivery, consistency and runtime with explicit
  boundaries between broker delivery, Redis projection and browser receipt.
  `docs/runbooks/observability.md` is the operator route for missing signals,
  export outages, backlog interpretation and trace correlation.

## Phase 14 load-testing map

- `load-tests/prepare.py` creates labeled, isolated demo users/auctions through
  HTTP and writes an ignored fixture manifest. `common.js` provides bounded
  outcome classification; `normal-auction.js`, `hot-auction.js`,
  `distributed-auction.js`, `final-minute.js`, `final-ten.js`,
  `duplicate-retries.js`, `duplicate-burst.js` and `websocket-fanout.js`
  express the measured workloads. The final-ten script uses client time only
  to pace launch; Rails/PostgreSQL still decides bid legality.
- `load-tests/benchmark.sh` orchestrates a separate read-only warm-up, pinned
  k6 container run, environment/telemetry capture and database check.
  `capture.py` records PostgreSQL, container and Prometheus snapshots;
  `report.py` generates a concise run report. `wait_closed.py` observes the
  independent closer after closing/challenge load stops.
- `apps/api/script/benchmark_verify.rb` independently checks auction history,
  price/leader, maximum ceilings, revision/outbox continuity and duplicate
  command effect against PostgreSQL, including recorded 90-second extension
  transitions, final close/winner and challenge command records. [Results](benchmarks/README.md)
  retain machine output separately from fixture data; [Session 2 analysis](benchmarks/phase-14-session-2.md)
  classifies the observed limits without changing auction business logic.

## Phase 15 profiling map

- `config/puma.rb` enables an opt-in private local Puma control socket for
  real backlog/thread stats. `lib/observability/db_pool_diagnostics.rb`
  separates Active Record checkout from blocking pool queue wait;
  `config/initializers/performance_diagnostics.rb` installs the hooks.
- `lib/observability/cpu_profile.rb` runs an opt-in bounded StackProf capture.
  `script/performance_sample.rb` samples Puma, process CPU/RSS and FD types;
  `script/query_profile.rb` profiles representative Rack paths with actual
  PostgreSQL and sanitized SQL categories.
- `load-tests/benchmark.sh` triggers optional diagnostic captures without
  changing the Phase 14 workloads. [Session 1 evidence](benchmarks/phase-15-session-1.md)
  routes from concise conclusions to raw runs and profiler output.
- `config/environments/development.rb` accepts opt-in
  `PERFORMANCE_DISABLE_RELOADING=true` for isolated local comparison; normal
  development reloading remains the default. `load-tests/capture.py` excludes
  fixture command keys and digests, while `report.py` tolerates observations
  above finite histogram buckets. The [Session 2 report](benchmarks/phase-15-session-2.md)
  records the rejected Puma/pool experiments and runtime limits.
The [final review](benchmarks/phase-15-final.md) classifies retained
diagnostics, rejected tuning and the remaining measurement boundaries.

## Phase 16 chaos map

- `scripts/chaos/run.py` creates isolated auctions, snapshots direct SQL and
  public reads, applies bounded faults and invokes the PostgreSQL checker.
  `session2.py` orchestrates broker/consumer crash windows;
  `session2_api.py` exercises command ambiguity and API restart;
  `session2_api_only.py` compares PostgreSQL and Redis while API is stopped.
- `ChaosCrash` contains opt-in, local/test-only process-death boundaries.
  `KafkaOutboxPublisher` invokes it after broker confirmation;
  `KafkaAuditConsumer` invokes it after receipt/effect commit;
  `Idempotency::Executor` and `IdempotentBidding` invoke it before and after
  the command transaction. The hook targets one event or auction and is inert
  in production. `script/chaos_probe.rb` retains public counts and digests.
- `apps/web/e2e/realtime.spec.ts` includes an opt-in real Compose worker-outage
  browser test: explicit REST refresh recovers a missed hint, then a later hint
  triggers another REST read. It uses PostgreSQL-backed API results for truth.
- [Session 1](chaos/session-1.md), [Session 2](chaos/session-2.md), the
  [final review](chaos/phase-16-final.md) and
  [ExecPlan](plans/phase-16-execplan.md) index direct local evidence.

## Phase 17 local multi-instance map

- `docker-compose.yml` keeps `api` and adds `api-replica-b`; `api-proxy` owns
  localhost:3001. `infrastructure/api-proxy.conf` routes HTTP and WebSocket
  upgrades without affinity and bounds dead-upstream Cable connects to five
  seconds; `infrastructure/nginx-local.conf` fixes one local nginx worker for
  observable round-robin distribution.
- `apps/api/app/controllers/api/v1/base_controller.rb` emits the bounded
  development-only diagnostic instance header. `script/phase17_session1.rb`
  sends commands through the stable proxy and verifies uncached PostgreSQL
  results. [Session 1](multi-instance/session-1.md) and the
  [final review](multi-instance/phase-17-final.md) index evidence.
- The proxy's local `X-Hammerfall-Cable-Upstream` upgrade header lets the
  browser harness attribute a socket to a real container. `apps/web/scripts/phase17_session2_realtime.mjs`
  checks cross-process hints, browser REST refresh, missed hints and owner
  stop/rejoin. CDP records Cable creation, attempts, handshake and closure;
  the final upstream address identifies the actual socket owner after a proxy
  retry. `apps/api/script/phase17_session2_ambiguity.py` runs the two
  scoped command crash boundaries; `phase17_session2_deadlines.rb` measures
  real PostgreSQL lock chains for soft close, deadline and closer races. See
  [Session 2](multi-instance/session-2.md) for the live campaign and the
  [final review](multi-instance/phase-17-final.md) for closure and limits.
## Phase 18 local Kubernetes map

- `infrastructure/api-k8s.Dockerfile` and `web-k8s.Dockerfile` bake source
  into images; the web image runs the Next.js production build/server.
  `apps/web/src/lib/realtime/auction-subscription.ts` uses the web origin for
  Cable when the local port is 8080.
- `apps/api/app/controllers/health_controller.rb` and `config/routes.rb`
  expose `/ready` for a PostgreSQL query; Rails `/up` remains liveness.
  `spec/requests/health_spec.rb` proves their separate dependency behavior.
- `k8s/base/` declares the namespace, ConfigMaps, selectorless external
  dependency Services, API/web Services and nine application Deployments.
  `k8s/base/web-proxy.yaml` routes browser `/api` and `/cable` at runtime.
  `k8s/local/up.sh` joins kind to the Compose network, creates the local
  Secret/EndpointSlices, loads images and runs `db-prepare.yaml` before
  deployment. See [local setup](../k8s/README.md),
  [ADR-014](adr/014-local-kubernetes-process-orchestration.md) and the
  [final evidence](kubernetes/phase-18-final.md).
- `apps/web/scripts/phase18_k8s_cable.mjs` exercises real Chrome Cable socket
  loss and REST recovery on API pod deletion. The local setup pins kind v0.33's
  Kubernetes 1.36.4 node digest to avoid a kubectl 1.35/1.37 version skew.

## Phase 19 cloud integration map

- `apps/api/app/services/kafka_client_config.rb` supplies local or Managed Kafka
  OIDC/TLS settings to the existing publisher and two consumers; their event
  and offset logic remains in the original classes. `k8s/overlays/gcp/kafka-auth/`
  contains Google's non-Java loopback ADC helper beside each Kafka role.
- `apps/api/app/services/redis_connection_config.rb` supplies local or verified
  TLS settings to Sidekiq and `AuctionPublicProjection`; `config/cable.yml`
  uses PostgreSQL, not a Redis adapter. `apps/api/lib/secret_files.rb` loads
  mounted database URL/key files before Rails initialization and checks the
  Cloud SQL verified-TLS URL contract.
- `infra/terraform/bootstrap/` is the separately gated GCS state bootstrap;
  `environments/reference/` owns the safe default and project API gates;
  `modules/reference/` owns VPC, GKE, Cloud SQL private DNS, Artifact Registry,
  Secret Manager metadata/IAM, and separately gated Redis/Kafka resources.
  Root and module mock tests prove the disabled/default shape.
- `k8s/base/kustomization.yaml` renders the unchanged Phase 18 local base.
  `k8s/overlays/gcp/` owns cloud KSAs, CSI mounts, Kafka auth sidecars,
  Gateway/HTTPRoutes, health policies, image-digest inputs and suspended
  `db-prepare`. `render.py` requires concrete deployment inputs and
  `validate.rb` checks workload identity, secret mounts, routing and health
  against the rendered overlay and Terraform KSA lists. The
  [final report](cloud/phase-19-final.md) separates local/static proof from
  live-cloud prerequisites; no cloud resources have been created.

## Phase 20 final integration clients

- `apps/api/script/authenticated_smoke.rb` is the development-only HTTP helper
  for login, cookie/CSRF persistence and explicit-key authenticated requests.
  `scripts/smoke-*`, `apps/api/script/phase17_session1.rb` and
  `apps/api/script/phase20_final_replicas.rb` exercise the actual Rails transport;
  the final replica script checks A/B authentication, revocation, replay and
  competing bid serialization. `phase20_limiter_replicas.rb` checks shared Redis
  login quota across the two replicas.
- `apps/web/e2e/auth.ts` prepares real browser/API sessions. The auctions,
  realtime and security Playwright specs cover the Next rewrite, browser cookie,
  CSRF command, Cable, logout and same-user retry. `docker-compose.yml` leaves
  `NEXT_PUBLIC_CABLE_URL` empty locally so the client uses the browser host
  for host-only cookies on port 3001.
