# Code map

Paths below are relative to the repository root. Phase 4 coordinates commands through a PostgreSQL auction row lock.
There is no outbox, event publication, or realtime delivery.

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
- Actor: find existing User from supplied bidder_id; no authentication yet.
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
- Unchanged web page: `apps/web/src/app/layout.tsx`, `page.tsx`, and `page.test.tsx`.
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
