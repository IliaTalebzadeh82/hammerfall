# Code map

Paths below are relative to the repository root. Phase 2 coordinates commands through a PostgreSQL auction row lock.
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
  `transition_to!`, `check_transition_preconditions!`, `leading_bid` in that model.
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
- Writes: INSERT accepted Bid, then UPDATE Auction.current_price inside that transaction.
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
