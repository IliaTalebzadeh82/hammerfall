# Progress

## Phase 0 — Repository Foundation

Status: COMPLETE

Historical Phase 0 snapshot, verified on 2026-09-23. At that point Phase 1 had
not started. See the Phase 1 section below for the current state; the master
specification remains unchanged.

### Implemented

- Git repository on main, with coherent documentation, API, frontend, and
  infrastructure/verification commits; existing author configuration was retained.
- Simple monorepo: apps/api, apps/web, docs/adr, infrastructure, scripts, .github,
  and documented future load-tests/observability locations.
- Rails API application with ActiveRecord/PostgreSQL, UTC, built-in `/up`, RSpec,
  RuboCop, Brakeman, bundler-audit, and an empty schema with no business tables.
- Next.js App Router, TypeScript, React, Tailwind v4, official shadcn base-nova
  initialization and Button, minimal starting page, Biome, Vitest/Testing Library.
- Development Compose for PostgreSQL/API/web, loopback ports, health checks,
  persistent database/dependency volumes, bind-mounted code, non-root app users,
  and lockfile-aware dependency installation.
- GitHub Actions jobs for backend checks, frontend checks/build, and Compose smoke
  verification; no deployment credentials required.
- README, local setup, ADR-001, architecture/domain/invariant/learning/code maps,
  tooling choices, engineering journal, and concise future-phase documentation.

### Technical choices

Ruby 4.0.6; Bundler 4.0.19; Rails 8.1.3.1; PostgreSQL 18.6; Node 24.20.0;
Next.js 16.3.6; React 19.2.8; TypeScript 6.0.3; Tailwind 4.3.3; shadcn 4.21.0;
Biome 2.5.14; Vitest 5.0.1; rspec-rails 8.0.4.

See [tooling](tooling.md) for compatibility reasoning and primary-source links.
The environment had working Ruby, Node, Docker, and PostgreSQL client tooling;
versions were selected after inspecting it and checking package registries.

### Commands actually run and results

App commands below ran from their app directories with the documented environment.

| Command / check | Result |
| --- | --- |
| `bundle install`, `bundle lock --add-platform aarch64-linux` | Resolved and locked successfully |
| `bin/rails db:prepare`, `RAILS_ENV=test bin/rails db:prepare` | Development/test databases prepared against real PostgreSQL |
| `bin/rails db:migrate`, test equivalent, `bin/rails db:migrate:status` | Passed; no domain migrations; schema version 0 |
| `bin/rails runner` with Rails version and PostgreSQL server-version query | Booted Rails 8.1.3.1; connected to PostgreSQL 18.6 |
| `bin/rails zeitwerk:check` | Passed |
| `bundle exec rspec` | 2 examples, 0 failures: health request and real isolated test-database connection |
| `bundle exec rubocop` | Passed, no offenses |
| `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | Passed, 0 warnings/errors |
| `bin/bundler-audit` | Passed, no known vulnerabilities in the checked advisory database |
| `bin/ci` | All backend steps passed, including setup, audit, autoloading, and specs |
| `npm install` / Docker `npm ci` | Locked installation succeeded; npm reported 0 vulnerabilities |
| `npm run lint`, `npm run format:check` | Passed |
| `npm run typecheck` | Next route type generation and TypeScript passed |
| `npm test` | 1 Vitest/Testing Library test passed |
| `npm run build` | Production build passed; starting page statically rendered |
| `npm run start -- --hostname 127.0.0.1 --port 3100` | Started; HTTP 200; title and starting-page content verified; temporary server stopped afterward |
| `./scripts/check` | Full native verification passed |
| `docker compose config --quiet` | Passed |
| `docker compose up --build --wait --wait-timeout 240` | Both app images built; PostgreSQL, API, web all healthy |
| Container RSpec with `-e RAILS_ENV=test` | 2 examples, 0 failures |
| Container frontend lint, formatting, type checks, Vitest | All passed |
| `curl --fail` at API `/up` and frontend `/` | Both HTTP 200 |
| Container `id` checks | Both app services run as UID/GID 1000, not root |
| Shell syntax checks and `git diff --check` | Passed |

The GitHub-hosted workflow itself has not run: no remote repository was configured.
Equivalent local checks and container smoke commands above were actually executed.
Initial dependency compatibility errors and the container test-environment guard
were resolved and retested; see [engineering journal](engineering-journal.md).

### Design decisions

[ADR-001](adr/001-modular-monolith.md): one Rails application owns future business
logic; PostgreSQL owns authoritative state; Next.js is presentation. Extract services
only for demonstrated scaling, availability, lifecycle, workload, or ownership needs.

No empty domain abstractions, business models, Kafka, Redis, Sidekiq, Kubernetes,
Terraform, or observability infrastructure were added. Framework adapters not yet
needed are omitted. No current auction guarantee is claimed.

### Known limitations / unresolved work

- No remaining Phase 0 blocker. GitHub-hosted CI still needs a remote push to run.
- `/up` tests liveness, not database availability or domain correctness.
- The web page has no API integration; authentication, auctions, bidding, real-time
  updates, end-to-end testing, and load tests belong to later phases.
- Development-only containers and dummy local credentials are not production deployment.
- SWC's performance advisory is documented; tests pass with the chosen compatible plugin.

The verified development services are left running: frontend on localhost:3000,
API on localhost:3001, PostgreSQL on localhost:5432. Use `docker compose down` to
stop/remove containers while preserving data volumes. The temporary port-3100
production smoke server was stopped.

### Next phase

Phase 1 — Core Auction Domain, only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md and docs/progress.md, then implement Phase 1 only: users, auctions, bids, explicit auction state transitions, a basic versioned REST API, PostgreSQL schema and constraints, validation, and RSpec coverage. Update the domain model, invariants, architecture, learning guide, code map, and progress docs. Preserve the verified Phase 0 foundation. Do not start Phase 2 or introduce later-phase infrastructure. Run the relevant checks and Docker verification, make coherent commits, and report results and unresolved decisions.

## Phase 1 — Core Auction Domain

Status: COMPLETE

Historical Phase 1 snapshot, verified on 2026-09-24. At that point Phase 2 had not started. Phase 0 commits and frontend
source are preserved, and masterprompt.md is unchanged.

### Implemented

- User with minimal display-name identity; Auction with explicit persisted
  lifecycle, exact money, time window, current price and nullable winner; Bid as
  an accepted immutable fact with auction/bidder references.
- Reversible PostgreSQL migration, committed schema, NOT NULL/FK/CHECK constraints,
  bounded positive money, allowed statuses, time ordering, price floor, and
  winner-only-when-closed check. Indexes cover bid history and leader selection.
- Explicit create/edit/schedule/activate/close/cancel/place_bid methods. No workflow
  mutations in callbacks, state-machine gem, or extra application-layer framework.
- Sequential minimum rule: starting_price for first bid, then current_price plus
  minimum_increment. Bid insertion and price update share a transaction/savepoint.
  A nested caller rescuing failure cannot commit only the bid.
- Versioned JSON API: user create/list; auction create/list/show/draft PATCH;
  schedule/activate/close/cancel POST actions; bid list/create. Bounded ID-cursor
  pagination, deliberate presenters, and stable expected-error envelopes.
- Small development-only seeds, guarded against overwriting existing domain data.
- Domain, request, database-constraint, rollback, and seed tests. Executable live
  HTTP smoke script added to the existing Compose CI job.
- Domain/API/invariant/architecture/learning/code-map docs, ADR-002, and corrected
  supporting readiness/security/failure notes.

### Design decisions

- Integer EUR cents, 1..1,000,000,000,000 per monetary field. No floating point,
  coercion of numeric strings/fractions, conversion, or multi-currency feature.
- current_price is stored: equals starting_price before bids and the latest
  accepted amount afterward. Atomicity is tested; concurrency isolation is not
  claimed. No explicit lock, optimistic version, or coordination mechanism exists.
- Lifecycle: draft -> scheduled -> active -> closed; cancellation from draft,
  scheduled, or active only before any accepted bid. Repeated target-state actions
  are no-ops; closed/cancelled are terminal. All terms freeze after draft.
- Status is lifecycle authority; bids also require starts_at <= application time
  < ends_at. Manual activation/closure only; close requires reaching ends_at.
- Current leader is highest bidder while active; winner is stored only at close.
  Closed auctions without bids have no winner. There is no retraction/refund policy.
- IDs provide stable ordinary history, not concurrent acceptance/commit ordering.
- Supplied bidder_id is demo identity, not authentication. Lifecycle endpoints
  also have no authorization; this remains a local development system.

### Commands actually run and results

| Command / check | Actual result |
| --- | --- |
| `bundle update json` | Locked compatible JSON 2.21.2; Rails 8.1/JSON 3 positional-options incompatibility resolved |
| Development/test `bin/rails db:prepare` | Passed against PostgreSQL 18.6 |
| `RAILS_ENV=test bin/rails db:rollback STEP=1`, then `db:migrate` and `db:prepare` | Reversed and reapplied the full migration successfully; development data was not rolled back |
| `bin/rails db:seed` twice | First run created 3 users, 3 auctions, 4 bids; rerun skipped without changing data |
| `bundle exec rspec` (final suite) | 164 examples, 0 failures |
| `bundle exec rubocop` | 43 files, no offenses |
| Root smoke script checked with API RuboCop configuration | 1 file, no offenses |
| `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | 0 errors, 0 warnings |
| `bin/bundler-audit` | No vulnerabilities reported by the checked advisory database |
| `bin/rails zeitwerk:check` | Passed |
| `bin/ci` after final domain changes | All backend steps passed; 164 examples, 0 failures |
| `./scripts/check` | Full native backend/frontend check sequence passed; subsequent backend additions were reverified by final bin/ci and container suite |
| Frontend `npm run lint`, `format:check`, `typecheck`, `npm test`, `npm run build` | Passed; 1 frontend test; successful production build; no frontend source changes |
| `docker compose config --quiet` | Passed |
| `docker compose up --build --wait --wait-timeout 240` | API image rebuilt with compatible parser; API/web/PostgreSQL healthy |
| Container test DB preparation, RSpec, and autoload check | Passed; final container RSpec run: 164 examples, 0 failures |
| `docker compose exec -T -e API_BASE_URL=http://127.0.0.1:3000 api ruby < scripts/smoke-api` | Created/edited/scheduled/activated an auction; accepted two bids (201); rejected low bid (422); verified active leader; closed/reclosed (200); rejected post-close bid (422); verified unchanged history and final winner |
| `git diff --check` | Passed |

The initial request suite exposed the JSON compatibility bug. A later focused test
reproduced nested-transaction partial persistence; the savepoint fix passed the
regression and full suite. One extra blank line caught by lint was corrected.
No failed check was disabled. Diagnosis is recorded in engineering-journal.md.

GitHub-hosted Actions has not run; the workflow and its equivalent local/container
commands are verified locally. This is not evidence of concurrency correctness or
production readiness.

### Commits

- `ebecab4` — fix(api): keep JSON parser compatible with Rails 8.1
- `bdcf1a4` — feat(domain): add auction lifecycle and sequential bid persistence
- `a158a70` — feat(api): expose versioned auction operations and HTTP smoke checks
- Documentation completion commit: `docs: record verified Phase 1 semantics and limits`

The documentation commit's own hash is intentionally not embedded in its content.
Existing Phase 0 history was not amended or rewritten.

### Known limitations and decisions to review before Phase 2

- **Phase 1 establishes correct single-operation semantics. Cross-instance/concurrent
  bid serialization is introduced in Phase 2.** Concurrent bid or lifecycle calls
  may still violate price/history/winner relationships. Reload and savepoints are
  not concurrency control.
- App-clock time checks and manual close are not race-safe distributed closure.
  There is no scheduler or automatic activation. Ended active auctions reject bids
  but remain active until explicitly closed.
- API reads can span multiple queries without a consistent concurrent snapshot.
  Active leader lookup is a separate indexed query per active auction in a list;
  performance has not been benchmarked.
- No authentication/authorization, request idempotency, automatic bidding, outbox,
  messaging, caching, realtime, or later infrastructure has been introduced.
- Review the EUR-only assumption, amount bounds, positive starting price,
  cancellation-before-bids policy, frozen scheduled terms, and ordinary-ID history
  contract before choosing Phase 2 ordering/coordination semantics.
- Review how the future locking strategy interacts with all auction mutations and
  nested transaction lifetimes; race-safe closing itself remains Phase 4 work.

No unresolved Phase 1 blocker remains. Development services are left running on
localhost:3000 (web), localhost:3001 (API), and localhost:5432 (PostgreSQL). Demo and
labelled smoke records remain for inspection; no user data was deleted.

### Next phase

Phase 2 — Correct Concurrent Bidding. Begin only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, docs/domain-model.md, docs/invariants.md, and the ADRs. Implement Phase 2 only — Correct Concurrent Bidding: choose and document PostgreSQL concurrency control, serialize bid validation/insertion/current-price updates, define authoritative bid ordering, preserve increment and stale-bid rejection rules, and add real PostgreSQL concurrency tests using separate connections. Verify competing bids, rollback, stale requests, and absence of lost updates. Create docs/adr/auction-concurrency-control.md and update invariants, learning guide, code map, and progress. Run relevant checks and Docker/API verification, make coherent commits, and report evidence and limitations. Do not start Phase 3 or add automatic bidding, distributed closing, idempotency, or later-phase infrastructure.

## Phase 2 — Correct Concurrent Bidding

Status: COMPLETE

Historical Phase 2 snapshot, verified 2026-09-24. At that point Phase 3 had not begun. Phase 0/1 history, masterprompt.md,
frontend source and dependency locks are unchanged.

### Implemented and concurrency strategy

- PostgreSQL SELECT FOR UPDATE through Auction#reload(lock: true), inside a
  transaction/savepoint, serializes bidding per auction across Rails processes.
  Lock/reload precedes status/window/minimum decisions. Application time is sampled
  after waiting, rather than at method entry. Stale objects are refreshed.
- Bid insertion and stored current-price update remain atomic; a failure after
  INSERT rolls back history and ordering even if an outer transaction rescues it.
- Existing edit/lifecycle commands acquire the same row lock before deciding;
  waiting bids recheck status, and waiting close sees committed accepted history.
  This does not introduce a scheduler or distributed time/closing redesign.
- Integer EUR cents, first-bid starting price, subsequent price-plus-increment,
  active leader versus formal winner, and explicit closure semantics are preserved.
- ADR-003 compares pessimistic locking, optimistic version/retry and conditional
  compare-and-swap. Row locking has the simplest local proof, without retry
  amplification or additional infrastructure. No Ruby mutex or distributed lock.

### Authoritative ordering and API

- Positive NOT NULL bigint Bid.sequence, UNIQUE(auction_id, sequence), assigned
  MAX(sequence)+1 under the auction lock. Normal immutable history starts at 1;
  rejected/rolled-back attempts consume no number. The contract is strictly
  increasing auction-local order, not global order, FIFO arrival or unconditional
  gaplessness in the presence of privileged history changes.
- Maintenance migration backfills legacy sequential history by per-auction ID;
  rollback drops ordering metadata without dropping bid data. It cannot recover
  unknown historical concurrent commit ordering. API writers were stopped for the
  original development migration; existing seed/smoke rows were preserved.
- New unique index replaces (auction_id,id) for sequence history/MAX lookup.
  Auction primary key remains the lock lookup; the existing amount-descending
  leader index and bidder/winner reference indexes remain. No speculative indexes.
- Bid responses expose sequence. Bid history uses after_sequence and
  meta.next_after_sequence. Obsolete after_id on bid history is explicitly 400;
  user/auction list cursors remain unchanged. Clients cannot supply sequence.
- Stale contenders receive 422 bid_too_low with price/minimum from fresh locked
  state, without SQL/lock implementation details. Later bids may change that state.

### Tests and actual concurrency verification

`spec/integration/concurrent_bidding_spec.rb` contains nine real PostgreSQL examples:

1. Two valid-looking bids, independent backend PIDs, consistent final history/price.
2. A lower waiter with a preloaded stale Auction rejects after a higher bid commits.
3. Twelve distinct bidders contend; accepted sequence, increments, price and leader agree.
4. Eight equal bids yield exactly one acceptance and seven domain rejections.
5. Cancellation commits before a waiter proceeds; the bid rechecks status and rejects.
6. Another auction finishes while the first auction remains locked.
7. A real temporary SQL CHECK fails the price UPDATE after bid INSERT; both writes
   roll back, and a subsequent bid receives sequence 1. No ActiveRecord lock mocks.
8. The time window expires during lock wait; fresh time rejects the contender.
9. A waiting close selects the just-committed bidder as its stored winner.

Only this group sets use_transactional_tests=false. Fixtures commit and are visible
across independent connections; workers load their own model instances. Queue
barriers hold two checked-out PostgreSQL sessions before simultaneous bidding, and
pg_blocking_pids proves controlled waiters actually block on the holder. Many
contenders queue for the default pool of three; this is not twelve simultaneous
PostgreSQL sessions. Owned records are cleaned after threads finish; all ordinary
specs retain transactional fixtures.

Final repeated run: seeds **1 through 20**, **9 examples each**, **180 examples,
zero failures**. An earlier 20-run pass also succeeded before the additional
checkout barrier. This is bounded correctness evidence, not stress confidence.

Mutation verification: replacing the three command reload(lock: true) calls with
plain reload caused **7 failures out of 9**, seed **43814**, with the final barrier.
The mutant was loaded only in the test process; production source was unchanged.
Failures included duplicate sequence errors, a parent-FK/unique-index deadlock,
stale lifecycle/time acceptance and missing winner. The intended lock-before-child-
write order resolves the competing lock cycle; no broad retry was added. The
restored implementation passed native and container full suites.

### Actual concurrent HTTP demonstration

Executed scripts/smoke-concurrent-bids with:

```sh
API_BASE_URLS=http://127.0.0.1:3001,http://127.0.0.1:3002 ./scripts/smoke-concurrent-bids
```

Port 3001 was the Compose Rails process; port 3002 was an independent native Rails
process connected to the same development PostgreSQL. Each request opened its own
HTTP connection, and requests alternated processes. The temporary process was
stopped afterward; this adds no multi-instance deployment infrastructure.

| Auction / scenario | Actual responses | Accepted history (sequence: amount cents) | Final state |
| --- | --- | --- | --- |
| 9 / twelve amounts 10000..15500, step 500 | 4 × 201; 8 × 422 bid_too_low | 1:12000, 2:14000, 3:15000, 4:15500 | price 15500; leader 30; winner null |
| 10 / eight amounts 10000 | 1 × 201; 7 × 422 bid_too_low | 1:10000 | price 10000; leader 21; winner null |

The script verifies every response against committed history, fresh rejection
minimums, increments, sequence uniqueness/order, final price and leader. Labelled
rows remain for inspection. Accepted counts depend on scheduling; these are actual
outcomes, not fixed expected counts or performance numbers. Sequential smoke also
passed on auction 11/user 31: two accepts, low rejection, close/reclose, post-close
rejection and unchanged history/winner.

### Full verification actually run

| Check | Result |
| --- | --- |
| Development migration forward and test db:prepare | Passed; existing development history backfilled |
| Test db:rollback STEP=1 then db:migrate with three interleaved bids across two auctions | Passed; original IDs, amounts, sequences and stored prices preserved after reapply; owned test rows cleaned |
| Native full RSpec | 178 examples, 0 failures |
| Final concurrency group, seeds 1..20 | 180 examples, 0 failures |
| Lock-removal mutation, seed 43814 | 9 examples, 7 expected failures; normal source unchanged |
| bin/ci | All steps passed: setup, RuboCop, gem audit, Brakeman, autoloading, test DB and 178 specs |
| RuboCop | 45 backend files, no offenses; both root Ruby smoke scripts also pass with explicit apps/api/.rubocop.yml |
| Brakeman / bundler-audit | 0 warnings/errors; no known vulnerabilities in checked advisory DB |
| ./scripts/check | Full native backend/frontend checks passed |
| Frontend lint, format:check, typecheck, test, build | Passed; 1 test, successful production build; source unchanged |
| docker compose config / up --build --wait --wait-timeout 240 | Passed; db, api and web healthy |
| Container test DB preparation and full RSpec | 178 examples, 0 failures (final seed 36592) |
| Live API /up and web / | HTTP 200 |
| Sequential and two-process concurrent HTTP smoke | Passed with actual results above |
| git diff --check | Passed |

After an interruption, temporary logs/processes were gone and services were down;
Compose was restarted and the final migration, checks and HTTP demonstration above
were repeated. Initial cleanup/clock/scanner issues and the mutation deadlock are
explained in engineering-journal.md. No check was disabled. GitHub-hosted Actions
has not run; local/container equivalents were executed. The workflow now includes
the concurrent HTTP script in addition to its sequential smoke.

### Commits

- `f5295ac` — feat(api): serialize auction commands and assign authoritative bid sequences
- `0eff1e2` — test(api): verify concurrent bids through live HTTP requests
- Documentation completion commit: `docs: record verified Phase 2 concurrency guarantees`

The documentation commit does not embed its own hash. Earlier phase history was
not amended or rewritten.

### Guarantees, limits and review before Phase 3

Concurrent normal manual bidding now has fresh validation, atomic mutation, unique
acceptance ordering and consistent committed price/history. Existing lifecycle
commands participate in the same serialization. Winner remains unset until close.

A hot auction's row lock is the deliberate throughput bottleneck. Long transactions
increase wait time; queued requests consume database connections. No fairness,
unbounded scalability, throughput target or latency number is claimed. Other
auctions can proceed independently. Unexpected database failures propagate; no
blanket retry can mask lock-order bugs or ambiguous commits.

Still absent: automatic bidding, distributed clock/closing policy, scheduler,
soft-close, idempotency, authentication/authorization, rate limiting, messaging,
external projections and all later infrastructure. Multi-query reads are not a
consistent snapshot. Validation-bypassing SQL remains outside workflow guarantees.
This is not production readiness or real-money approval.

Before Phase 3 review private maximum visibility, tie priority, proxy price rules,
manual versus automatic interactions, generated-bid ordering, maximum modification/
cancellation and lock ordering. The current latest-bid-equals-price invariant must
be reconsidered explicitly if proxy pricing changes its meaning. Preserve one
auction serialization boundary and distinguish hidden maxima from public history.

Development services remain on localhost:3000/3001/5432. Only the extra temporary
port-3002 process was stopped. No user-owned development data was removed.

### Next phase

Phase 3 — Automatic Bidding, only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, docs/domain-model.md, docs/invariants.md, docs/architecture.md, docs/learning-guide.md, docs/code-map.md, docs/api.md, all ADRs, and the current bidding code/tests. Implement Phase 3 only — Automatic Bidding: private maximum bids, an explicit deterministic proxy-bidding algorithm, documented tie behavior, manual/automatic interactions, maximum modification/cancellation policy, and real PostgreSQL concurrency tests. Preserve Phase 2 auction-row serialization, fresh validation, atomic state/history updates, authoritative ordering, and maximum privacy. Document any necessary changes to price/leader invariants with examples and an ADR. Run full relevant checks, repeated concurrency tests, migrations, Docker and live API verification; update learning/code-map/progress docs and make coherent commits. Stop after Phase 3. Do not add distributed closing, soft-close, idempotency, Redis, Sidekiq, Kafka, outbox, WebSockets, authentication redesign or later infrastructure. Report actual evidence, limitations, and decisions requiring review.

## Phase 3 — Automatic Bidding

Status: COMPLETE

Verified 2026-09-24. Phase 4 has not begun. Phase 0–2 history, masterprompt.md,
frontend source and dependency lockfiles are unchanged.

### Implemented and proxy rules

- MaximumBid is a private binding instruction, separate from visible accepted Bid.
  One current instruction exists per auction/bidder. It stores bounded integer EUR
  maximum_amount and independent durable auction-local priority_sequence.
- Auction#set_maximum! and existing #place_bid! both lock/reload the auction in a
  transaction/savepoint before lifecycle/time checks and resolution. The cohesive
  Bidding::ProxyResolver owns pricing and ordered generation of at most two rows.
- First maximum opens at starting price. A leader adding/increasing protection emits
  nothing. Lower challengers visibly reach their ceiling, then incumbent counters
  at the minimum required price. Higher challengers first exhaust incumbent
  protection, then offer only enough to win (or their exact manual amount).
- Automatic prices clamp at the user's ceiling, allowing a final partial increment.
  Fixed minimum_increment remains; no dynamic increments, reserve or extension.
- Equal ceilings use earlier priority, including an existing proxy versus a later
  equal manual bid. Challenger then priority winner may both have equal-price rows.
  Visible amounts are non-decreasing, refining Phase 2's strict increment invariant.
- Explicit current_leader_id is selected by pricing/priority rules and saved with
  price. The final emitted row represents that leader and current_price. winner_id
  remains null while active; existing explicit close copies the leader under lock.
- The pairwise algorithm relies on all prior nonleaders being exhausted at/below
  current price or losing an equal-ceiling tie after each completed command. The
  decision table and this settled-state reasoning are documented in ADR-004.

### Tie semantics and maximum modification policy

New and increased maxima receive MAX(priority_sequence)+1 under the auction lock.
The priority for a raised ceiling reflects the raise, not its earlier smaller
amount. Earlier commitment to an equal ceiling wins. Visible Bid.sequence remains
independent, unique and monotonically increasing per auction.

Increase is allowed; same amount is a no-op preserving priority after eligibility
checks; lower amounts raise maximum_bid_cannot_decrease; cancellation is unsupported
and normal destruction raises. Exhausted instructions remain stored. A nonleader increase
at/below public price is rejected without priority/state mutation; a later competitive
increase can resolve again. New or increased nonleader protection must exceed
current price, allowing a partial increment; a leader must cover its existing price.

### Privacy and API

PUT `/api/v1/auctions/:id/maximum-bid` accepts:

```json
{"maximum_bid":{"bidder_id":42,"maximum_amount":50000}}
```

It returns 200 with only auction_id, bidder_id and accepted=true. There is no maximum
read/list/delete endpoint. New expected errors are maximum_bid_cannot_decrease and
maximum_bid_too_low, without stored private amounts. Existing eligibility/validation/
not-found error conventions remain. A manual POST returns its own accepted row,
which can be outbid by a counter committed in the same operation.

Public auction/history omit maximum_amount, priority_sequence and origin. Explicit
presenters and acknowledgements avoid generic model dumps. Rails filters private
parameters, SQL bind values and model inspection; captured-log tests verify this.
Visible bids can legitimately reach an exhausted ceiling but never identify it as
a maximum or disclose unused protection. This is **representation/data privacy,
not complete authorization-based secrecy**: actor IDs remain unauthenticated,
impersonation/probing are possible, and operators can read plaintext database rows.

### Schema and migrations

- maximum_bids with NOT NULL/FKs, positive bounded maximum, positive priority,
  unique (auction_id,bidder_id) and unique (auction_id,priority_sequence).
- Auction.current_leader_id foreign key/index; existing Phase 2 history backfills
  its leader from latest accepted sequence, including closed auctions.
- Bid.origin with manual default and allowed manual/automatic CHECK; old rows become
  manual. Existing public sequence constraints remain unchanged.
- Maintenance migration with writers stopped. The down migration refuses to delete
  private commitments when any MaximumBid exists. Rollback/reapply was tested on
  three interleaved legacy bids across two auctions; IDs, amounts, sequences and
  prices were preserved and leader/origin were correctly restored. Refusal with an
  existing private instruction was separately verified before owned test cleanup.

### Concurrency and tests

The transaction owns fresh validation, instruction/priority write, all visible
INSERTs and the final price/leader UPDATE. SQL failure rolls all of these back,
including when an outer transaction handles the failure. No asynchronous responses,
process-local correctness locks, external calls or broad database retries exist.

New coverage:

- 30 deterministic/model examples: first max, manual leader protection, increases,
  same/lower/cancel policy, manual below/equal/above ceiling, proxy lower/higher/tied,
  final partial increments, refreshed priority, exhausted instruction reactivation,
  multiple previous bidders, dormant tie-priority regression, invalid money, inactive/time states, close tie winner,
  and an 80-operation reproducible mixed-command invariant stream.
- 10 PostgreSQL concurrency examples: different/equal simultaneous maxima, manual
  below/above versus max, increase versus challenger, two existing increases,
  same-user competing increases, closed/cancelled waiters, and real SQL failure
  after two generated rows with complete rollback and subsequent sequence reuse.
- 5 request/privacy examples: actual public JSON and other-actor responses, errors,
  unavailable read/cancel routes, repeated values/missing actors, and captured debug
  request/SQL logs plus model inspection filtering.
- 11 real SQL constraint examples cover NULL/range/FK/uniqueness/origin/leader rules.
- All Phase 2 examples remain; shared committed-data/session helpers moved to
  spec/support/committed_auction_context.rb. Only the two concurrency groups disable
  transactional wrappers. Workers use separate connections/model instances and
  explicit Queue barriers; pg_blocking_pids verifies controlled lock waits. Cleanup
  targets owned committed records; ordinary tests remain transaction-wrapped.

Repeated both concurrency groups with **seeds 1–20**: **19 examples per run,
380 examples, zero failures** (180 manual + 200 maximum examples). These are bounded
correctness tests, not load or reliability confidence beyond what was exercised.

Lock-removal experiment loaded a separate mutated Auction definition only in the
RSpec process: replacing reload(lock: true) with plain reload caused **9 failures
out of 10 new proxy concurrency examples**, seed **43814**. Duplicate priorities,
inconsistent contests and stale lifecycle acceptance were detected. Actual source
remained locked and the normal full suite passed afterward. No sabotage committed.

### Live verification

Ran `scripts/smoke-proxy-bidding` using two independent Rails processes sharing
PostgreSQL: Compose at localhost:3001 and temporary native Rails at localhost:3002.
The final simultaneous requests alternated processes and used independent HTTP
connections. Then queried PostgreSQL to verify private commitment priority and
public sequence/leader state. In the final rerun Alice was user 51; Bob was user 52.

| Scenario / auction | Actual visible amounts in sequence order (cents) | Price / leader |
| --- | --- | --- |
| A / 64: Alice maximum 30000, Bob manual 20000 | 10000, 20000, 21000 | 21000 / Alice |
| B / 65: Alice maximum 30000, Bob maximum 40000 | 10000, 30000, 31000 | 31000 / Bob |
| C / 66: Alice maximum 30000, Bob maximum 30000 | 10000, 30000, 30000 | 30000 / Alice |
| D / 67: concurrent maxima 30000/40000 across processes | 10000, 30000, 31000 | 31000 / Bob |

All four had visible sequences 1,2,3 and winner=null. Database inspection confirmed
Alice priority 1 and Bob priority 2 where both instructions existed. Scenario C's
last two rows were Bob 30000 then Alice 30000; earlier durable priority selected
Alice. Public responses contained no ceiling/priority/origin fields, and scenario A
never exposed Alice's unused 30000. The script retained labelled rows for inspection.

Existing sequential smoke also passed (auction 41/user 38). Existing live manual
concurrency smoke passed: auction 62 accepted 3 of 12 competing increasing bids,
rejected 9, final price 15500; auction 63 accepted one of eight equal bids, rejected
seven, final price 10000. Accepted counts reflect actual scheduling, not a benchmark.
The temporary port-3002 process was stopped after verification.

### Lock-held work observation

A local sql.active_record monotonic-notification probe measured SELECT FOR UPDATE
completion to COMMIT completion, with two warmups and twenty samples per case.
Manual-only challenge: median **19.294 ms**, range **12.700–32.287 ms**.
Challenge plus proxy counter: median **23.894 ms**, range **13.548–30.760 ms**.
This run observed about 4.6 ms more median lock-held work. Other development activity
was present; these numbers are a small local observation, not isolated benchmark
results, a capacity estimate or stable latency claim. The extra private reads and
visible write hold the same serialized auction row longer. Proper measurement
remains Phase 14/15. Only sample-owned records were removed.

### Full verification actually run

| Check | Result |
| --- | --- |
| Native full RSpec | 234 examples, 0 failures |
| Combined concurrency repeated seeds 1..20 | 380 examples, 0 failures |
| Proxy mutation without locks | 10 examples, 9 expected failures; normal source unchanged |
| Development/test forward migrations | Passed; existing development history preserved |
| Test rollback/reapply with existing legacy bids and separate populated-max refusal | Passed; leader/origin/sequence/price verified |
| bin/ci | All backend steps passed, including final 234 examples |
| RuboCop | 54 backend files, no offenses; new root smoke script passed using API config |
| Brakeman / bundler-audit / Zeitwerk | 0 security warnings; no known vulnerabilities in checked advisory DB; autoload check passed |
| ./scripts/check | Full native backend/frontend checks passed |
| Frontend lint / formatting / typecheck / test / production build | Passed; one test; frontend source unchanged |
| Compose config | Passed |
| Compose up --build --wait --wait-timeout 240 | Initial Ruby manifest lookup returned registry HTTP 403; later retry built both images using cached layers and all services were healthy |
| Cached API startup while registry was unavailable | Passed with bind-mounted current code and unchanged dependencies |
| Container test DB prepare/full RSpec | 234 examples, 0 failures, final seed 57790 |
| Four proxy HTTP scenarios and sequential/concurrent manual smoke scripts | Passed, results above |
| API /up and frontend / | HTTP 200 |
| git diff --check | Passed |

No runtime/dependency change or scanner suppression bypassed the temporary registry
failure. The build retry resolved it; no no-cache build is claimed. GitHub-hosted CI
has not run. Local/container equivalents passed and CI now includes proxy smoke.
Initial association-validation issues and the dormant equal-price priority edge case
were fixed and retested, not hidden; see engineering-journal.md. Final native/
container suites, twenty combined concurrency runs, mutation and two-process live
scenarios were repeated after the eligibility fix. No Phase 4 functionality or later infrastructure was added.

### Commits

- `d0b110d` — feat(api): resolve binding private maxima under the auction lock
- `b3e0a3c` — test(api): exercise proxy bidding across live Rails processes
- `af6ff24` — fix(domain): reject noncompetitive increases before assigning proxy priority
- Documentation completion commit: `docs: record verified Phase 3 proxy bidding semantics`

The documentation commit intentionally does not contain its own hash. Phase 0–2
history was not amended or rewritten.

### Guarantees, known limitations and review before Phase 4

Binding protection, minimum winning proxy pricing, durable tie priority, non-
decreasing visible history, atomic price/leader/max resolution, separate formal
winner and cross-process PostgreSQL serialization are implemented and tested.

One hot auction remains a serialized row-lock bottleneck; extra proxy work increases
lock duration and waiting connections. No fairness or throughput guarantee exists.
Maxima are plaintext and unauthenticated actor IDs do not protect against impersonation.
No maximum-change history, cancellation, reserve, dynamic increments, idempotency,
notifications, outbox, realtime, caching or other later infrastructure is present.
App-clock eligibility and explicit close remain; automatic responses never extend
ends_at. Generic multi-query reads need not share one commit snapshot. Privileged
SQL/validation bypass remains outside normal workflow guarantees.

Before Phase 4 review authoritative clock source, close versus an entire multi-bid
proxy transaction, retry-safe/repeated close, winner finality under equal ceilings,
scheduler delays, and whether one logical contest or each generated row triggers an
extension. Define extension window/duration and original end semantics explicitly.
Preserve binding maximum privacy and the auction lock order during that work.

Development db/api/web remain running on localhost:5432/3001/3000. Live demo rows
are retained; the extra native process and sample-owned timing rows were cleaned.

### Next phase

Phase 4 — Auction Closing + Soft Close, only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, docs/domain-model.md, docs/invariants.md, docs/architecture.md, docs/learning-guide.md, docs/code-map.md, docs/api.md, all ADRs, and the current lifecycle/manual/proxy code and tests. Implement Phase 4 only — Auction Closing + Soft Close. Define and document authoritative time, closing ownership, delayed and duplicate close behavior, winner finality, and fixed anti-sniping extension rules. Specify how one logical proxy contest with multiple generated bids affects extension. Preserve the PostgreSQL auction-row lock, fresh validation, private binding maxima, deterministic priority, atomic history/price/leader state, and public privacy. Add real separate-connection/process tests for bidding/proxy/closing/extension races and repeated or stale closers. Use only infrastructure justified within Phase 4; do not introduce Phase 5 idempotency keys or later Redis, Sidekiq, Kafka, outbox, WebSockets, observability, authentication redesign, Kubernetes or Terraform. Run relevant full checks, repeated concurrency tests, migrations, Docker and live multi-process demonstrations. Update ADRs, invariants, learning guide, code map and progress, make coherent commits, report actual evidence and limitations, and stop after Phase 4.
