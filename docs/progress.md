# Progress

> Historical phase log. Older recommended prompts below mention `masterprompt.md`;
> those are evidence, not current instructions. Start with `AGENTS.md`,
> `docs/handoffs/latest.md`, the current `docs/phases/` specification and the
> active ExecPlan when resuming; use `docs/context-map.md` for targeted reads.
> Search this file's phase headings for specific historical evidence only.
> The original is archived at `docs/archive/masterprompt-original.md`.

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

## Phase 4 — Auction Closing + Soft Close

Status: COMPLETE

Implemented and verified on 2026-09-24/25. Phase 5 has not begun. The Phase 0–3
sections above are historical snapshots; ADR-005 and current domain/API docs govern
new time and closing behavior.

### Implemented

PostgreSQL decision clock; half-open deadlines; exactly-once-per-command soft close;
original and closure timestamps; due-only idempotent close; finalized winner;
independent Rails closer role and Compose process; real concurrency, arithmetic,
rollback, process and HTTP demonstrations. No later-phase infrastructure or frontend
auction/countdown UI was introduced. Pricing, private binding maxima, durable priority,
auction-local sequence, explicit leader and representation privacy remain intact.

### Authoritative time and deadline semantics

AuctionClock.now reads uncached PostgreSQL clock_timestamp() on the current
connection **after** Auction reload(lock: true). Each bid/max/close command captures
one value. Schedule/activate use the same source; production at: overrides were
removed. NOW()/CURRENT_TIMESTAMP/transaction_timestamp() are unsuitable because they
retain transaction-start time after a lock wait. The mutation experiment below proves
both kinds of expired waiter would be accepted with that stale clock.

Active status and starts_at <= decision_time < ends_at permit bidding; at equality
or later an active row rejects auction_ended with public ends_at. Before start it
rejects auction_not_open; inactive rows retain invalid_auction_state. HTTP arrival,
Rails time and transaction start confer no eligibility. Legality is assessed at the
locked decision, not at physical COMMIT. Outer callers still own the outer commit
and lock lifetime.

### Soft-close rule and extension unit

`0 < ends_at - decision_time <= 60 seconds` adds exactly **90 seconds to existing
ends_at**. At 37 seconds remaining this leaves 127 seconds, not 90. Manual bids,
new maxima and actual maximum increases are accepted external commitments. Each
qualifying command extends once, independently of whether resolution emits zero,
one or two Bid rows. A leader's protection increase can extend with no price/history
change. Identical max, decreases, insufficient bids and other rejections do not
extend. There is no arbitrary cap; later commands in later windows can extend again.

Auction#persist_bidding_action! runs after synchronous resolution and saves final
price/leader/end within the same transaction as all max/priority and Bid changes.
ProxyResolver no longer independently saves Auction. Real SQL rejection of the
calculated extension rolls back the entire manual or maximum contest.

### Schema, timing fields and migration evidence

- starts_at remains the earliest eligible time; activation remains explicit.
- original_ends_at is initialized/synchronized through draft creation/editing and
  frozen when scheduled. Generic updates cannot change live effective deadlines.
- ends_at is the effective legal deadline after extensions.
- closed_at is the DB finalization decision timestamp, not physical commit time;
  delayed closure can record it later than ends_at without legalizing late bids.
- Public Auction JSON includes all four UTC fields and retains current_leader_id
  after closure, separately from winner_id.
- SQL requires original end non-null, ends_at>=original end, closed_at iff closed,
  closure at/after effective end, and null-safe winner/leader equality when closed.
  The partial active (ends_at,id) index supports bounded due discovery/order.

Migration 20260924030000 locks auctions and backfills original end from old ends_at.
Legacy closed_at uses GREATEST(updated_at,ends_at), an explicit **estimate**, because
older phases never recorded authoritative closure time. No historical clock accuracy
is claimed. Forward, rollback and reapply preserved every old column byte-for-byte
across **48 users, 22 auctions, 52 bids and 14 private maxima**. Snapshot SHA-256:
`0b9bef823cfd6d8258605f6dfadb7a1a6711e22f56d962275732c20d572a38fc`.
After live Phase 4 activity, rollback correctly refused detectable timing-history
loss and retained schema version 20260924030000. Export/preserve new timing history
before a real downgrade. Development seeds still skip existing data; the closed
example uses an explicit fixture import instead of a production clock override.

### Closing ownership and winner finality

Auction#close! is the only finalizer. It begins a transaction/savepoint, locks and
reloads, reads DB time, and returns unchanged for closed or active-not-due auctions.
A due active row stores status=closed, winner=current_leader and closed_at in one
save. Other states reject invalid_state_transition. The close API means finalize
if due (200 unchanged active when early), never force close. Closing emits no Bid,
never chooses a winner from raw maxima, and preserves the explicit leader. No bids
means nil leader/winner. Duplicate calls preserve winner/closed_at/updated_at.
Closed auctions cannot reopen, bid, change max or extend through normal commands.

**No lazy finalization through rejected bidding.** Late bid/max requests reject
without persisting changes, even if status is still active. The closer or explicit
close later materializes lifecycle. Scheduler delay can delay status, never the
legal bidding window. This avoids an exception rolling back intended lazy closure.

### Scheduler/closer behavior

bin/auction_closer boots the same Rails application/image, a process role rather
than a microservice. AuctionCloser discovers up to 100 active/due IDs, ordered by
end/id against a sampled DB cutoff, then invokes close! for each. Candidate discovery
is only a hint; locked fresh state/time decide. The fixed cutoff supports an index
range scan instead of a volatile per-row clock predicate.

Default poll interval is 1 second; interval and batch size are configurable.
--once runs one bounded pass and fails if transient candidate errors made it partial.
SIGINT/SIGTERM stop after in-flight work; poll sleeps check the stop flag every
100ms. The executable defaults lock/statement timeouts to 5s/10s using PGOPTIONS.
Known transient failures log/retry on later discovery; unknown per-auction failures
log ID/class and propagate. Startup/shutdown logs were observed. Compose restarts
on failure. No exact materialization SLA, leader election, Redis or Sidekiq exists.
Multiple closers may duplicate discovery, but row serialization and no-op close
preserve one final winner/timestamp.

### Race tests, boundaries and repeated runs

Nine new PostgreSQL race/atomicity examples cover:

- Manual bid or protection increase holds the first lock, extends before commit,
  then a different session discovers the old **due** committed deadline and waits.
  Its stale Auction reloads after the extension commits and safely skips closure.
- Closer holds first after expiry; waiting manual/max commands reject closed state.
- Manual/max transactions demonstrably start before expiry, wait on a real row lock
  until the DB deadline passes, then reject auction_ended despite stale transaction
  time. The still-active row subsequently closes normally.
- Eight independent closer contenders produce identical winner/closed_at/updated_at
  and no synthetic Bid.
- Real SQL failure on the calculated extension rolls back private state, priority,
  both visible rows, price, leader and deadline, for manual and maximum commands.

Exact pure-arithmetic cases pass: 60.001 seconds -> no extension; 60.000, 37 and one
microsecond -> +90; equality and after deadline -> expired, no extension. Integration
uses real DB time and observed pg_blocking_pids, with no mocked locks/clocks. Ordinary
expired fixtures explicitly arrange deadlines rather than pretending Rails travel_to
controls PostgreSQL. Waiting helpers independently query actual DB time so clock
sabotage cannot also freeze the observation mechanism.

The slow repeated-extension test uses **separate committed transactions**, two real
successive windows roughly 32 seconds apart, and independent sessions verifying
each committed end. No deadline/clock manipulation occurs between the two bids.
Final review moved it out of RSpec's outer fixture transaction to establish this
stronger claim. Other tests cover empty first maxima, two-row maximum contests,
protection-only creation/increase, identical max, rejected bids/decreases, frozen
fields, query caching and closer configuration/failure/shutdown behavior.

Repeated Phase 2/3/4 concurrent_* groups with **seeds 1–20**: **28 examples per run,
560 examples, zero failures** (180 manual, 200 maximum, 180 closing). The long
committed repeated-window case runs in the full suite rather than these repetitions.
These are bounded correctness exercises, not load or reliability/throughput claims.

### Sabotage results

Separate /tmp definitions were loaded only into RSpec; source was never unlocked.

- Replace the production DB wall-clock with transaction_timestamp(): **2/2 selected
  pre-expiry waiter tests fail**, seed 404. They incorrectly return an accepted Bid
  or MaximumBid after expiry. The observation helper still uses real DB wall time.
- Remove only close!'s locking reload: **3/9 closing tests fail**, seed 404: manual
  stale candidate, max stale candidate and duplicate closed_at stability.
- Restore normal definitions: **9/9 closing examples pass**, seed 404; final full
  native/container suites also use the normal implementation.

Early failures from connection leases, overlapping test invocations, and the first
sabotage observation helper were corrected rather than counted as successful
verification. See engineering-journal.md for those findings.

### Live multi-process verification

Two independent APIs (Compose localhost:3001 and temporary native localhost:3002)
shared PostgreSQL. scripts/smoke-closing used real HTTP requests and additional
independent Ruby/Rails closer processes. Ordinary closer was stopped for controlled
stale/delayed scenarios and restarted afterward. Labelled records were retained.

| Scenario | Actual result |
| --- | --- |
| A, auction 68 | Late manual bid adds exactly 90; leader 53 |
| B, auction 69 | Proxy history 10000,20000,21000; exactly +90, leader 53 |
| C, auction 70 | Another process discovers old due row while accepted extension is uncommitted; observed lock wait; reload leaves active at old end+90 |
| D, auction 71 | Closer first; blocked HTTP bidder rejects; winner 53; closed_at 2026-09-24T13:29:50.499212Z |
| E, auction 72 | Two closer sessions 20419/20420 discover the same due row; identical winner and closed_at 2026-09-24T13:29:51.308929Z; one visible bid remains |
| F, auction 73 | Real deadline passes with ordinary closer stopped; active late bid returns auction_ended; eventual close has nil winner and unchanged end |

Existing concurrent HTTP smoke also passed across both APIs: auction 74 accepted
6/12 increasing bids, final price 15500; auction 75 accepted 1/8 equal bids, final
price 10000. Sequential lifecycle smoke passed on auction 77, including repeated
closure and post-close rejection. Corrected proxy privacy smoke passed on auctions
78–81: respective histories 10000/20000/21000, 10000/30000/31000,
10000/30000/30000 and concurrent 10000/30000/31000. Its old substring search for
origin falsely matched original_ends_at; exact JSON-key checks retain the privacy
assertion. Maxima/priority/origin remain omitted. Native SIGINT and Compose SIGTERM
both logged clean shutdown; a separate bin/auction_closer --once ran successfully
while the ordinary closer was also running.

### Full verification

| Check | Actual result |
| --- | --- |
| Final native full RSpec | 273 examples, zero failures, seed 425; includes separate-commit real repeated windows |
| Final container full RSpec | 273 examples, zero failures, seed 426; same final source |
| bin/ci | Passed: setup, Ruby lint, bundler-audit, Brakeman, Zeitwerk, test prepare, 273 examples (seed 11652), before the final test-only transaction-wrapper refinement |
| Repeated Phase 2/3/4 concurrency | 560 examples, zero failures, seeds 1–20 |
| Arithmetic boundary tests | Six exact cases passed |
| SQL failure/constraints | Passed in native/container suites |
| Forward / rollback / reapply | Passed with identical pre-existing records; live-history downgrade guard separately refused |
| Ruby lint | 64 API files and all three changed root smoke scripts passed |
| Security/autoload | Brakeman zero warnings; bundler-audit no known vulnerabilities in checked database; Zeitwerk passed |
| scripts/check | Passed full backend (then 271 examples), frontend and Compose checks |
| Frontend lint / format / types / test / production build | Passed; one frontend test; no frontend source changes |
| Compose config / image build / startup | Passed; both images built with cached layers; api/db/web healthy and closer running |
| API and closer process smoke | Passed, live scenarios above; one-shot and clean signals verified |
| git diff --check | Passed |

GitHub-hosted CI was not run. Local/native/container equivalents were run; CI now
also executes an independent closer one-shot. Development images use mounted current
application code. No no-cache build, capacity claim or exact scheduling SLA is made.

### Commits

- `6fd8fde` — feat(domain): enforce database-clock closing and atomic soft close
- `4c2533b` — feat(runtime): run and verify the Rails auction closer
- `a6e5058` — test(domain): verify repeated extensions across committed transactions
- Documentation completion commit: `docs: record verified Phase 4 deadline and closing guarantees`

The documentation commit intentionally does not contain its own hash.

Phase 0–3 history was not amended or rewritten.

### Guarantees and known limitations

One PostgreSQL auction row serializes bid/max/close decisions across processes;
post-lock DB wall time defines legality; complete proxy settlement and extension
are atomic; stale/duplicate closers revalidate; winner/closed_at are final. Active
status may lag, never the bidding deadline. Source constraints and domain tests
support these claims without relying on scheduler punctuality.

A hot row and waiting connections remain bottlenecks. Duplicate closers can duplicate
work or wait behind hot candidates. No throughput, fairness, FIFO or status-freshness
SLA exists. PostgreSQL wall-clock corrections and outages remain operational risks.
Long outer transactions delay commit/lock release. Raw SQL/validation bypasses are
outside workflow guarantees. Private maxima remain plaintext and supplied actor IDs
are unauthenticated; there is no identity secrecy or production readiness claim.
No retry deduplication, realtime, event publication, projections, notifications,
metrics stack or later infrastructure has been added. Legacy closed_at is an estimate.

### Review before Phase 5

Persist replay outcomes with the authoritative mutation so a lost response cannot
run settlement or extend again. Define key scope, fingerprinting, conflict errors,
retention and what failures are persisted. Replays after closure must not rerun
current deadline validation and accidentally replace a prior accepted response.
Keep lock order coherent between idempotency records and the auction row; preserve
private maximum filtering. Close itself is idempotent, but bidding retries are not.
No Phase 5 implementation has begun.

### Next phase

Development api/db/web/auction-closer remain running. The temporary port-3002 API
was stopped after verification; labelled live demonstration records remain.

Phase 5 — Idempotency, only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, current domain/API/invariants/architecture/learning-guide/code-map docs, all ADRs, and the bidding/proxy/closing code and tests. Implement Phase 5 only — Idempotency. Add PostgreSQL-backed Idempotency-Key persistence, request fingerprinting and concurrent duplicate handling. Define key scope, conflict responses, retention, replay responses and failure policy. Atomically persist outcomes with auction mutations so retries cannot duplicate bids, private-max changes, proxy settlement or soft-close extensions. Test lost-response retries, concurrent duplicates across Rails processes, conflicting payloads, rollback and replay after deadline/closure. Preserve post-lock PostgreSQL clock authority, auction serialization, winner finality, binding private maxima, priority and public privacy. Add real PostgreSQL concurrency tests and live multi-process evidence. Run full checks, migrations and Docker verification; update ADRs, docs and progress; create coherent commits with a clean working tree. Do not implement Phase 6 or later infrastructure, and stop after Phase 5.

## Phase 5 — Idempotency

Status: COMPLETE

Implemented on 2026-09-25. Earlier phase sections above are historical snapshots;
this section supersedes their statements about missing retry protection. Phase 6
has not started. No frontend source or auction/closer domain algorithm was changed.

### Implemented and protected operations

PostgreSQL IdempotencyRecord stores actor FK, constrained operation, key digest,
request fingerprint, processing/completed status, public JSONB response, HTTP status,
timestamps and expires_at. SQL checks constrain digest shape, terminal response
shape/status and retention. Completed records are readonly through normal model
writes. POST `/api/v1/auctions/:auction_id/bids` and PUT
`/api/v1/auctions/:id/maximum-bid` require a 1–255 visible-ASCII Idempotency-Key.
Missing/invalid keys return 400; all existing smoke clients now supply keys.

### Key scope, fingerprinting and conflict semantics

Logical scope is actor + operation + key; exact PostgreSQL uniqueness is
UNIQUE(actor_id, operation, key_digest), where key_digest is SHA-256 of the raw key.
The request fingerprint is SHA-256 of fixed-order JSON: api_version v1, operation,
integer auction_id, integer actor_id and sorted semantic arguments. Parsed scalar
types are preserved; whitespace, object order and unrelated headers are irrelevant.
No raw key/request/private maximum is persisted in the idempotency table.
Same scope/key with a different amount, type or auction returns 409
idempotency_key_conflict without mutation or disclosure of the original payload.
Other actors/operations have independent scopes.

### Atomicity, lock ordering and concurrent duplicates

IdempotentBidding resolves the actor, then Executor opens the outer transaction and
INSERTs ownership before Auction lookup, row lock, deadline clock or evaluation.
PostgreSQL unique-index conflicts wait for the owning transaction. Matching committed
outcomes replay; owner rollback lets the waiter acquire ownership and execute.
Auction's existing requires_new transactions are nested savepoints. Key ownership,
all proxy/public/private state, priority, price, leader, extension and terminal
snapshot commit together. Snapshot SQL failure rolls everything back. Processing
is never deliberately committed; no recovery lease or external lock is needed.

### Replay semantics and failure policy

Both initial and replay responses use the same JSONB-normalized public snapshot,
including exact response bytes, status, accepted bid ID/sequence and historical
error details. Replays add Idempotency-Replayed: true and never touch Auction.
They work after price/leader changes and after closure, even while another session
holds the Auction row lock. A replay is a past command outcome, not current state.

Retained outcomes: 200/201 success; deterministic domain/validation 422; execution
404 (missing Auction). Malformed requests, bad keys and missing actor fail before
claim and are not retained. Conflicts do not replace the original record. Unexpected
exceptions, SQL/connection failures and snapshot failures roll back and leave the
key retryable; 500 responses are never cached. Private maxima/priority/origin remain
absent from public responses; raw keys and ceilings are absent from captured logs.

### Retention

Seven days by default from claim transaction DB time, configurable 1–365 days.
Expiry means eligible for pruning: an expired row still reserves its key while
physically present. `bin/rails idempotency:prune` deletes one completed, expired
batch, default 1000 and maximum 10000, using FOR UPDATE SKIP LOCKED. Only deletion
allows key reuse. No background scheduling or Sidekiq was added. The actual CLI
removed one expired fixture, preserved current records and allowed a fresh execution
under that removed key. Replaying it before pruning returned the stored outcome.

### Concurrency, rollback and lost-response tests

Thirteen new committed PostgreSQL concurrency examples use independent connections:
ten duplicate manual commands; ten late proxy contests; ten new/increased maxima;
both operations' conflicting payloads; replay while a closed Auction is locked;
SQL terminal-write failure for both operations; waiting owner commit/rollback;
and a fresh key waiting past the actual DB deadline. Assertions cover complete
state and row counts, not just replay headers. Separate request/model/constraint
specs cover canonicalization, malformed keys, historical rejections, privacy,
retention, SQL uniqueness/FKs/checks and unexpected exceptions.

A lost manual response replays the same accepted bid after another bidder changes
price/leader and after closure. An old maximum acknowledgement replays after a
later increase and closure without changing priority. A proxy retry creates no
new contest rows; a late retry adds no second 90-second extension. Snapshot failure
leaves no key or mutation, and retry succeeds with sequence 1 and one extension.

### Live multi-process evidence

Actual HTTP clients targeted independent Rails APIs on ports 3001 (Compose) and
3002 (native), sharing PostgreSQL. Development-only labelled fixture setup is
explicit; production decision clocks were not replaced.

| Scenario | Observed result |
| --- | --- |
| Manual auction 82 | Ten duplicates: one execution, nine replays; bid 196, sequence 1; end 09:54:20.794192Z → 09:55:50.794192Z |
| Proxy auction 83 | One execution, nine replays; bids 197/198/199, sequences 1/2/3, amounts 10000/20000/21000; one extension |
| Maximum auction 84 | New and increased maxima each executed once across ten requests; one visible bid 200; priority advanced only to 2 |
| Conflicts auctions 85/86 | Manual statuses 409/201; maximum statuses 409/200; only the winning payload applied |
| Lost response auction 82 | Original bid 196 replayed after price became 50000 and closure selected winner 73; state unchanged |
| Old maximum auction 84 | Original 200 replayed after increase and closure; priority remained 2 |
| Historical rejection auction 87 | Original minimum 10000 replayed while current price was 50000 |

Timestamps above are UTC on 2026-09-25. The existing sequential/manual/proxy smokes
also passed with mandatory keys. The closing smoke passed again for auctions 96–101:
manual/proxy extension, stale discovery, lock-blocked late rejection, two closer
sessions agreeing on finalization, and eventual closure of an expired active row.
The regular closer was stopped for its controlled scenarios and restarted afterward.
One-shot closer execution and the container pruning task also passed.

### Sabotage results

Temporary /tmp loaders left production code unchanged. Bypassing coordination
failed all 13 concurrency examples (seed 505): conflicting manual payloads both
returned 201 and maximum payloads both returned 200; ten maximum requests executed
ten times; replays waited on Auction instead of resolving ownership. Moving auction
validation before replay failed both after-closure request tests: saved 201/200
became 422. Normal request/concurrency code then passed 31 examples, seed 505.

The first sabotage run exposed a test cleanup defect: worker assertion exceptions
are not StandardError. Two test fixtures leaked and caused nine collection/seed
failures in the first final bin/ci run. The shared cleanup now explicitly handles
RSpec assertion exceptions. Only those identified test rows were removed; sabotage
was repeated and all five tables were verified empty before final normal checks.
This was a test harness correction, not a weakened assertion or domain workaround.

### Migrations and preservation

Forward, empty-table rollback and reapply preserved every pre-existing domain row:
67 users, 36 auctions, 83 bids and 23 private maxima. All-column snapshot SHA-256:
`9f9dd4e27a78fc0b30c907ff6880de3df38b093d5d323941b3e7dd1574584d76`.
A later populated downgrade correctly refused to discard retained outcomes. No
private snapshot values are included here. A live downgrade needs an explicit
preservation/retention plan.

### Verification results

| Check | Actual result |
| --- | --- |
| scripts/check | Passed: full backend 324 examples, seed 20812; frontend checks; Compose config |
| Final native bin/ci | Passed: setup, 73-file lint, gem audit, Brakeman, autoload, prepare, 324 examples, seed 21790 |
| Final container full RSpec | 324 examples, zero failures, seed 525; includes real repeated-window test |
| Final repeated Phase 2–5 concurrency | 820 examples, zero failures, seeds 1–20; 41 examples/run |
| Repetition breakdown | Manual 180, maximum 200, closing 180, idempotency 260 |
| Root smoke script lint | All five files passed using the API RuboCop configuration |
| Security/autoload | Brakeman zero warnings; gem audit no known vulnerabilities in checked database; Zeitwerk passed |
| Frontend lint / format / types / test / build | All passed; one Vitest test; no frontend source changes |
| Migration preservation / guarded downgrade | Passed as described above |
| Compose final config / image build / startup | Passed; api/db/web healthy and closer running |
| Live two-API idempotency and previous smokes | All passed as described above |
| Closer one-shot / container prune task | Passed; final prune found zero eligible rows |
| Sabotage detection / cleanup | Expected failures observed; repeat cleanup left all five test tables empty |
| git diff --check | Passed |

GitHub-hosted CI was not run. The checked-in workflow runs the full backend suite,
updated protected-endpoint smokes and now the bounded pruning task. Development
images use bind-mounted current code; builds used cached layers. No throughput,
latency, fairness or capacity claim is made.

### Guarantees and known limitations

Client retries under a retained matching key return the original outcome without
repeating bid/proxy/max/priority/soft-close effects. PostgreSQL uniqueness and one
transaction provide cross-process coordination and crash atomicity. Phase 2–4
serialization, post-lock DB wall time, winner finality and privacy remain intact.

Actor IDs remain unauthenticated. Internal Auction methods are intentionally outside
the HTTP key contract. Digests are not encryption or protection from privileged
operators; private maxima remain plaintext in their existing table. Expired records
need operational pruning and storage planning; pruned keys may execute again.
Hot rows and duplicate-key waits consume connections. Long caller transactions
delay durability and lock release. Raw SQL bypasses, multi-region writes and API
snapshot/fingerprint version migration require separate designs. No Redis, Sidekiq,
Kafka, outbox, realtime, projections or frontend functionality was introduced.

### Commits

- `883c19f` — feat(api): atomically persist and replay bidding command outcomes
- `0d7c6da` — test(runtime): verify cross-process idempotent bidding and retention
- Documentation completion commit: `docs: record verified Phase 5 retry guarantees`

Earlier history was not rewritten. The documentation completion commit intentionally
does not contain its own hash.

### Review before Phase 6 and next phase

Development api/db/web/auction-closer remain running. The temporary port-3002 API
was stopped after verification; labelled development demonstration rows remain.

Phase 6 — Frontend, only on a new explicit request. Review client command identity:
generate one key per new intention and retain that same key and payload for an
ambiguous transport retry. Show historical replay success without treating its
snapshot as fresh auction state; refetch public auction/history. Do not expose
private maxima or imply that supplied bidder IDs are authentication. Countdown is
presentation; server DB time and the returned deadline remain authoritative.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, apps/web/AGENTS.md, current API/domain/invariants/architecture/learning-guide/code-map/running-locally docs, all ADRs, and the existing frontend and bidding/closing/idempotency code and tests. Implement Phase 6 only — Frontend: auction listing and detail, live countdown, manual bid and automatic-bid forms, public bid history, status indicators, responsive UI and shadcn/ui components using the real Rails API. Generate one Idempotency-Key per new user intention and reuse the same key and payload for transport retries; handle replay, 400/409/422 responses and ambiguous failures clearly, and refresh public state after commands. Preserve server-authoritative deadlines, privacy of maximum amounts/priority/origin, and the explicit unauthenticated demo identity limitation. Add meaningful frontend tests and browser verification, run full checks and Docker verification, update docs/progress and learning material, create coherent commits with a clean working tree, and stop after Phase 6. Do not add fake features, authentication, Action Cable, Redis, Sidekiq, Kafka, outbox or later-phase infrastructure.

## Phase 6 — Frontend

Status: COMPLETE (2026-09-26)

### Implemented routes and architecture

`/` redirects to `/auctions`; `/auctions/[id]` presents a real auction and its
sequence-paginated accepted bids. A shared shell provides the demo actor selector,
recovery banner and navigation. Domain components live in
`apps/web/src/components/auction`; public types and the fetch client live in
`apps/web/src/lib/api`. Next's transparent `/api/v1` rewrite reaches Rails using
`API_ORIGIN`; it adds no BFF business logic. shadcn primitives support the forms,
alerts, badges and loading layouts. Text-focused cards use actual API data.

Demo selection loads paginated real users and persists only the chosen actor ID
in localStorage. It explicitly does not authenticate anyone. Switching actors
clears unsubmitted form values; unresolved commands lock actor selection.

### Money, time and server authority

Money input is parsed from digit groups into integer EUR cents, with explicit
precision/bounds validation and no rounding of excessive decimals. Display uses
Intl.NumberFormat. The isolated countdown ticks from returned `ends_at`, adjusted
by an approximate response-time offset. The minimal Rails `X-Server-Time` header
is fresh presentation metadata, including rescued errors; it is not PostgreSQL
clock authority and does not change stored idempotency response bodies/statuses.
At zero the UI checks authoritative state instead of closing the auction or
choosing a winner. Refreshed extensions update the countdown.

Public GETs determine price, leader, winner and history. Terminal command results
trigger fresh auction/history reads. Explicit refresh and tab visibility also
refresh state. Superseded reads are aborted/guarded against stale replacement.
There is no optimistic price/leader update or simulated realtime transport.

### Commands, recovery and privacy

Manual and private maximum forms create one opaque crypto.randomUUID per new
intention. Maximum copy explains increase-only, binding behavior. The accepted
command message remains distinct from refreshed leadership after automatic bids.
One tab-wide immutable intention binds operation, actor, auction, cents and key.
It is saved in sessionStorage before transmission and retained across reloads.
Storage failures block transmission rather than silently lose retry identity.

Network failures, timeouts, malformed success responses and 5xx are ambiguous.
Safe retry sends the same payload/key explicitly; it never blindly generates a
replacement. Replay acknowledges the historical result and refetches public
state. An explicit warned abandonment clears the local attempt, not a committed
server bid. One-hour client retry eligibility stays below the server's minimum
one-day retention; expired attempts require review/abandonment. Refresh alone
does not resolve ambiguity. Valid 400/404/409/422 error envelopes have terminal
feedback; stale minimum/price details are described as historical and followed
by fresh reads. Unexpected payloads remain conservative.

Public types/components select public fields and never render maximum amount,
priority or bid origin. Tests pass deliberately overbroad objects to prove this.
A user's unresolved maximum exists only in that tab's sessionStorage, not public
history, URLs, analytics or debug output. Descriptions render as React text.

### Responsive design and accessibility

The restrained cream/green interface has responsive cards and a two-column detail
layout that stacks on mobile. A mobile bidding anchor keeps forms reachable.
Long titles and EUR 1 billion values were exercised at 390, 768 and 1440 pixels;
forms and errors remain within the viewport and accepted history stays readable.
Labels, field-associated errors, visible focus, semantic table headers, skip
navigation, textual statuses and polite command feedback are implemented. The
countdown is not a once-per-second live announcement. Abandonment uses inline
confirmation, not a focus-trapping modal. This is not a formal accessibility audit.

### Verification evidence

The final verification results follow. The browser suite uses the actual
Rails API and ordinary closer, with labelled development records retained. For
response-loss recovery, Playwright forwards the real POST, observes Rails' 201,
then drops only the browser response. Reload and retry must carry exactly the
original key/body, return a replay, clear pending storage and leave four accepted
rows rather than a duplicate fifth row.

The Compose browser run passed all four cases: auction 114 covered manual/max,
stale rejection and committed-response-loss recovery; 115 closed through the
independent closer; 116 exercised long titles, large money and all three widths;
117 covered draft, scheduled and cancelled states. Countdown verification asserts
an automatic authoritative GET at zero before the explicit final refresh.

Playwright 1.63.0 used installed Chrome 154.0.8037.57 through
`PLAYWRIGHT_CHROMIUM_EXECUTABLE=/opt/google/chrome/chrome`. Bundled Chromium
installation was attempted but its download returned regional HTTP 403; this
was not treated as successful installation. Screenshots are generated under the
ignored `apps/web/test-results` directory. Browser output directories are also
explicitly excluded from Biome, avoiding lint/format failures on generated JSON.

The production build was served separately on port 3100 and passed the same four
browser tests in 12.7 seconds: auctions 118 (commands/replay), 119 (closure),
120 (responsive layout), and 121 (draft/scheduled/cancelled). This also verified
production hydration and the native API rewrite. The temporary production server
was stopped afterward; the Compose development stack remains available on port 3000.

| Check | Actual result |
| --- | --- |
| Final `scripts/check` | Passed; Compose config, backend and complete frontend checks |
| Final native RSpec in that check | 326 examples, zero failures; seed 9562 |
| Backend `bin/ci` | Passed; 326 examples, seed 46901; setup, audit, lint, autoload and DB preparation |
| Container full RSpec | 326 examples, zero failures; seed 606 |
| RuboCop / Brakeman / gem audit | 74 files without offenses; zero security warnings; no known vulnerabilities in checked database |
| Vitest / Testing Library | 61 tests in seven files, all passed |
| Frontend lint / format / types | Passed, including generated-output exclusions |
| Next production build | Passed; listing and dynamic detail route, plus favicon |
| Compose browser suite | Four passed in 14.6 seconds against real Rails and closer |
| Production browser suite | Four passed in 12.7 seconds against real Rails and closer |
| Responsive screenshots | Captured and visually inspected at 390/768/1440; long title, large price, error, focus and accepted history |
| Compose config / image build / startup | Passed; api/db/web healthy, closer running; cached build layers used |
| `git diff --check` | Passed |

The GitHub workflow now installs Chromium and runs the real API browser suite after
existing smoke checks. GitHub-hosted CI itself was not run. Screenshot paths from
the final production browser run are
`apps/web/test-results/auctions-responsive-forms--38c6a--history-and-keyboard-focus/`
(`detail-390.png`, `detail-768.png`, `detail-1440.png`, `listing-desktop.png`). They
are ignored generated artifacts, not checked-in fixtures. Existing backend tests
continue covering concurrency, proxy settlement, privacy, deadlines, closing,
soft close and idempotency; frontend work did not change those domain services.

### Known limitations and review before Phase 7

Refreshes can show stale state between requests; two GETs are not one atomic
snapshot. Actor IDs are unauthenticated. Pending private maxima are readable by
scripts with access to the tab's origin; sessionStorage is recovery, not secure
storage or coordination across tabs/devices. Closing the tab can lose recovery.
The retry horizon is deliberately conservative and depends on browser wall time;
server retention/pruning remains the real replay boundary. Server-time offset is
approximate and cannot decide deadline eligibility. Read failures can leave an
explicitly stale previous view. No performance, production readiness or hosted CI
claim is made. There is no Action Cable, WebSocket, SSE, Redis, notification or
later-phase infrastructure in this implementation.

Review ADR 007, the public field allowlists, GET race handling and command-result
versus current-state distinction before adding server-pushed updates. Keep stable
intentions and REST refresh/recovery when adding realtime behavior. A transport
connection must never become authority for bid acceptance, deadlines or winners.

### Commits

- `a7ef234` — feat(web): add typed auction transport and immutable command foundations
- `48f29f1` — feat(web): build auction views and recoverable bidding workflows
- `ad8ade6` — test(web): verify real bidding recovery and responsive browser flows
- Documentation completion: `docs: record verified Phase 6 frontend behavior`

The documentation completion commit intentionally does not contain its own hash.
Phase 0–5 history is preserved.

### Next phase

Phase 7 — Real-Time Updates, only on a new explicit request.

Recommended next prompt (exact):

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, apps/web/AGENTS.md, all ADRs, docs/frontend.md, and the current architecture, domain-model, invariants, API, consistency-model, learning-guide, code-map and running-locally documents. Inspect the frontend command/recovery code, public serializers, bidding/closing/idempotency services and tests. Implement Phase 7 only — Real-Time Updates, following the master plan. Add real server-pushed auction updates with Action Cable while preserving Rails/PostgreSQL authority, maximum/priority/origin privacy, stable idempotency intentions, historical replay semantics and fresh REST recovery. Handle connection loss, reconnects and stale/out-of-order updates explicitly; never infer acceptance, closure or winners from transport state or browser time. Do not add later-phase infrastructure or silently change domain semantics. Add meaningful backend/frontend/browser tests, run full regression/security/build and Docker verification, document actual evidence and remaining delivery limitations, update progress/learning/code-map/ADRs, create coherent commits with a clean working tree, and stop after Phase 7. Do not begin Phase 8.

## Phase 7 — Real-Time Updates

Status: COMPLETE — verified 2026-09-29

### Implemented and protocol

Action Cable now uses PostgreSQL in development/production and the isolated test
adapter in specs. `/cable` hosts a validated public AuctionChannel; exact origin
allowlists stay enabled, with production default deny. No Redis/Sidekiq was added.
The adapter carries invalidations across Rails processes with no new infrastructure.

Auction.public_revision is a nonnegative NOT NULL bigint, default zero for creation
and legacy rows. The existing locked explicit mutation advances it once for public
draft edits, lifecycle transitions, bidding settlement or extension. Proxy rows and
an extension are one logical action. Private-only protection changes, identical
maxima, rejected/rolled-back actions, replay, pruning and early/duplicate closes do
not advance or publish; private-only timestamps also remain unchanged.

The only application payload is `{type:"auction.changed.v1",auction_id,revision}`.
One central publisher runs through the current transaction's outermost after_commit;
rollback drops savepoint callbacks. Broadcast failure cannot change committed domain
or idempotency outcome. Maxima, priorities, bid origins, actor/command information
and keys never enter the notification. See ADR-008 and realtime.md.

### Browser recovery

The detail page owns one consumer after its first GET, refreshes on every subscription
confirmation/reconfirmation, ignores stale/equal hints and coalesces bursts into
serial REST reads. Older REST revisions cannot regress the display. Cleanup aborts
reads and disconnects the consumer. Cable health, REST errors and command state are
independent. Events never resolve an ambiguous intention; safe retry and historical
replay semantics remain intact. Listing pages retain explicit REST pagination.

### Actual multi-process and browser evidence

Independent Compose Rails A/3001 and native Rails B/3002 share PostgreSQL. HTTP
mutations through A reached actual sockets attached to B. Restored final protocol
proof: auction 133, revision 2 -> notification 3 -> REST 3; exact three-field payload,
stream isolation, malformed subscription rejection and disallowed-origin rejection
passed. The reusable script is apps/web/scripts/verify-realtime.mjs.

Initial separate-process two-client run passed all three realtime scenarios through
native frontend 3100 (HTTP A, Cable B). Auction 125 observed revisions 3,4, missed 5
while disconnected, then recovered 5 through reconfirmation REST with no replayed
event. Manual 100 and a challenge 200 against private protection 300 settled at 210
with three public rows. Auction 126 deadline advanced exactly 90 seconds, revision
2 -> 3. Auction 127 closed via the ordinary closer, revision 3 -> 4, winner 1; an
actual closure notification was observed. Tests use real deadlines, not clock overrides.

The final production Next frontend on 3100 also passed **3/3** realtime browser
scenarios against HTTP A/3001 and Cable B/3002: auctions 148–150 proved proxy
settlement/reconnect, 90-second extension and winner publication. Temporary native
servers were stopped afterward; the Compose stack remains running.

### Sabotage evidence

- Two independent temporary Rails processes on 3003/3004 with async adapter: the
  cross-process notification wait timed out (8 seconds). Restored PostgreSQL passed.
- Immediate publication replacing after_commit: 9 examples, 3 failures, exposing
  uncommitted visibility, outer rollback phantom and savepoint phantom messages.
  Runtime-only override was removed; normal tests pass.
- Removed stale/equal revision guard: stale-hint/coalescing test failed. Original
  source was restored and the complete frontend suite passes.

No sabotage is retained. The heartbeat capture bug found during the first full
browser run was fixed separately; that failed run is not successful evidence.

### Regression and operational checks

The full scripts/check run passed 349 backend examples and 73 frontend tests across
10 files, RuboCop, Brakeman, eager loading, lint, formatting, typecheck and production
build. An additional explicit maximum-replay notification spec was added afterward;
final native bin/ci passed **350 examples, 0 failures** (seed 38784), including
RuboCop, bundler-audit, Brakeman and eager loading. Frontend recheck passed
**73 tests / 10 files**, lint, formatting and typecheck. Complete Compose browser
suite passed **7/7** (1.7 minutes): auction 145 recovered missed revision 5,
146 extended exactly 90 seconds, and 147 closed with winner 1. Explicit npm audit
reported **0 vulnerabilities**. Five randomized repetitions of the
Phase 2–5 concurrency groups passed 41 examples each (205 total).

Docker image rebuild/startup passed; PostgreSQL/API/web health checks passed and the
ordinary closer runs. npm install reported zero vulnerabilities; backend bin/ci
includes bundler-audit and Brakeman. Production Next build also succeeded with HTTP
A and Cable B configuration. Migration down/up in a rolled-back test transaction
preserved all prior row fields, backfilled zero, and rejected nonzero downgrade.
No development database reset or hosted CI execution is claimed. Installed Chrome
was used through the documented executable fallback. Responsive screenshots at
390/768/1440 were captured; the 390px detail was visually inspected with connected
status, long title, large price and field error visible without horizontal overflow.

### Delivery and scaling limitations

Notifications are best-effort and ephemeral. Commit-before-broadcast crash can lose
a hint; a live connection is not proof of freshness. No durable log, replay, outbox,
queue, periodic reconciliation or exactly-once delivery exists. REST reads recover
current state but auction/history are separate observations. PostgreSQL listener
connections, shared pool contention and hot-auction fanout/read amplification need
measurement. Demo actor/lifecycle APIs remain unauthenticated.

### Review before Phase 8

Review WSS/proxy/origin settings, connection budgets, public-only privacy, revision
migration/downgrade policy, ephemeral delivery and retained command intentions.
Phase 8 must preserve synchronous PostgreSQL bid/deadline/winner authority and
safe retry; introducing a job queue does not make notifications durable automatically.

Next phase: **Phase 8 — Sidekiq + Redis**, only on a new explicit request.

Recommended prompt:

> Work in /home/uncleili/dev/ruby/hammerfall. Read masterprompt.md, docs/progress.md, apps/web/AGENTS.md, all ADRs, and the architecture, domain-model, invariants, API, consistency-model, realtime, frontend, learning-guide, code-map and running-locally documents. Inspect the auction locking, proxy, deadline/closer, idempotency and Phase 7 publication/recovery code and tests. Implement Phase 8 only — Sidekiq + Redis, following the master plan: add application background jobs, a notification pipeline and a scheduled reconciliation framework with explicit failure semantics. Keep PostgreSQL authoritative and bid acceptance, price resolution, deadline legality and winner finalization synchronous and atomic; Redis availability must not decide auction correctness. Make every job safely retryable and define duplicate, delayed, lost, reordered and failed-job behavior, bounded retries and operational recovery. Preserve public revision semantics, after-commit privacy, ambiguous client intentions and REST reconnect recovery. Explain any Action Cable adapter change with real multi-process evidence. Do not imply durable publication across the commit/enqueue gap, and do not add Phase 9 outbox or Phase 10 Kafka early. Test worker/Redis failure and recovery plus duplicate delivery; rerun all domain concurrency, backend/frontend/browser, security, production build and Docker checks. Update ADRs, progress, learning diagrams, code-map and operating instructions with actual evidence, create coherent commits and leave a clean working tree. Stop after Phase 8; do not begin Phase 9.

Implementation commits: `a21e28d` (transactional revisions/Cable) and `f0eff33`
(browser recovery, live verification and runtime configuration). Documentation is
committed separately after final verification. Phase 8 has not begun.

Final container RSpec passed **350 examples, 0 failures** (seed 59140). Applying
the final Compose setting had interrupted the first extra container run (exit 137),
leaving one auction/two users; the next run exposed that leftover test fixture.
After explicitly verifying hammerfall_test and clearing only its domain tables,
the full container rerun passed. Final Compose services are running; configured
health checks are healthy. Git diff whitespace checks passed.

## Phase 8 — Sidekiq + Redis

Status: COMPLETE — verified 2026-09-30. Phase 9 has not begun.

### Implemented and decisions

Sidekiq 8.1.7 and Redis 7.4 run as separate Compose roles. The Rails API does not
depend on Redis to boot or decide a bid. The existing PostgreSQL Action Cable
adapter, public channel, `public_revision` and browser REST recovery remain.
An outermost-commit callback now enqueues `AuctionChangedJob` with only auction ID
and revision. The job reads current PostgreSQL revision and broadcasts the exact
three-field `auction.changed.v1` hint. Duplicate, delayed and reordered jobs may
repeat a current hint without changing domain state. Redis enqueue failure is
logged after commit and does not alter an accepted bid or idempotent outcome.
A job broadcast/DB failure reaches Sidekiq's five retries and then the Dead set.
See ADR-009 for the adopted boundary and alternatives.

A separate scheduler enqueues `ReconciliationSweepJob` every 60 seconds by default
(minimum five; `--once` is operational). The job scans bounded 100-auction batches
up to a captured ID, using one SQL statement per batch with latest accepted Bid.
It reports price/leader/closed-winner drift by public auction ID only and never
repairs PostgreSQL. Phase 11 Redis projection and Phase 12 repair remain absent.
Compose Redis uses a local AOF volume; this is not a backup or event log. CI's
Compose job now probes Redis and schedules one sweep before its real browser suite.

### Verification actually completed

- Focused final job and committed-publication specs: 19 examples, zero failures.
- Native `./scripts/check` before the final two spec additions: 357 backend
  examples, zero failures; RuboCop (85 files), Brakeman (zero warnings), Zeitwerk,
  frontend lint/format/typecheck, 73 Vitest tests and Next production build passed.
  The final two specs were then covered by the full container run below.
- Final full container RSpec: 359 examples, zero failures (seed 5743). Targeted
  RuboCop after the additions passed eight files; `bin/bundler-audit` found no
  vulnerabilities. Compose config/build/start and all seven services passed their
  configured startup/health checks. Hosted GitHub CI was not run (no remote).
- Complete real-API Playwright suite: 7/7 in 1.6 minutes, including response-loss
  replay, proxy contests, reconnect, 90-second extension and autonomous winner
  publication through Sidekiq. Independent HTTP API A/3001 and Cable API B/3002
  script passed: auction 151 revision 2 → job hint 3 → REST 3, exact payload,
  stream isolation, malformed subscription and disallowed origin rejection. B was
  stopped afterward.
- Stopped Sidekiq, then accepted a real HTTP bid on labelled auction 153 at price
  10,000/revision 3. Notification queue grew from 0 to 3 (schedule, activate,
  bid); worker restart drained it and logs showed all three jobs completed.
- Stopped Redis, accepted a real HTTP bid on labelled auction 155 at price
  10,000/revision 3, and replayed the same key/body with status 201, unchanged
  JSON and `Idempotency-Replayed: true`. API logged
  `auction_notification enqueue_failed ... RedisClient::CannotConnectError`.
  Redis restart showed notification queue length zero: the missed hints were not
  reconstructed. The scheduler's one-shot command exited 1 while Redis was down,
  then succeeded after recovery. With Redis down again, the API restarted healthy
  and accepted a second bidder's 10,500 bid on auction 155 at revision 4.
- Enqueued a deliberately future revision (4 for current revision 3) on auction
  155; the real worker raised and Sidekiq's RetrySet held that job with
  `retry_count: 0`/`RuntimeError`. The exact test job was removed from RetrySet.
  This was a controlled worker-retry proof, not a claim of eventual delivery.
- Test-process-only sabotage: immediate publication before outer commit made the
  committed visibility spec fail (1/1); bypassing the job's current-revision read
  made the stale-hint spec fail (1/1); removing enqueue-error isolation made the
  committed idempotency success spec fail (1/1). The three `/tmp` overrides were
  not written to application source. Final normal tests passed afterward, and the
  test database had zero users/auctions/bids/idempotency rows after cleanup.

### Known limits and next boundary

There is still an unprotected PostgreSQL commit-to-Redis-enqueue gap. Failed
enqueue, Redis data loss, worker exhaustion/dead jobs or a later Cable failure can
lose a hint. A connected browser may stay stale until another recovery trigger.
Queue drain does not prove all committed mutations produced notifications. Jobs
can repeat, and the scheduler is neither exact-time nor singleton. Drift checks
report but do not repair; no Redis auction projection exists. No throughput,
capacity, backup/restore, authenticated identity, real-money readiness or hosted
CI claim is made. Development proof rows remain labelled; existing user data was
not reset. See the Phase 8 runbook and production-readiness document.

**Phase 9 readiness:** Phase 8 runtime, tests and runbook are complete. Phase 9
has not started: no outbox table/write, publisher, durable domain-event schema,
Kafka integration or delivery guarantee exists. A fresh explicit request should
start Phase 9 with its specification and the updated handoff; do not treat Redis
jobs as an outbox.

## Phase 9 — Transactional Outbox

Status: COMPLETE — verified 2026-09-30. The primary implementation
was committed as `5a032e6`; [the ExecPlan](plans/phase-09-execplan.md) holds the
compact Evidence Index and exact live observations.

### Implemented and boundaries

Each public auction mutation saves its authoritative state, increments
`public_revision` and inserts a versioned `auction.changed.v1` outbox row in
one PostgreSQL transaction. An enclosing idempotency transaction also owns the
stored command outcome. The row has stable UUID, auction ID/revision, database
occurrence time and retry/acknowledgment state, but no private maximum, priority,
origin or key. A unique auction/revision index defends identity. Draft creation
at revision zero, private-only changes, unchanged commands, rejections, duplicate
close and replay create no new public event.

An independent Compose publisher claims due committed rows using `FOR UPDATE
SKIP LOCKED`, enqueues the existing Sidekiq job, and marks published only after
Sidekiq returns a job ID. Failed enqueue persists class-only error and bounded
exponential backoff; retries continue until success or operator intervention.
Redis client network operations have a two-second timeout. Retry,
acknowledgment and pending-age calculations use PostgreSQL clock time. Aggregate logs expose
backlog, due, retries and oldest age. Different publishers may deliver revisions
out of order. The job reads current PostgreSQL revision and sends the same
public Cable hint. Acknowledgment means enqueue, not final delivery. See ADR-010.

### Failure, sabotage and regression evidence

- A Rails runner committed auction 163, a 10,000-cent bid, revision 3 and three
  outbox rows, then killed itself with SIGKILL (exit 137). A separate process
  read all three pending UUIDs. A separate publisher enqueued all three and
  real Sidekiq logs showed three completed `AuctionChangedJob`s.
- With Redis stopped and PostgreSQL healthy, a separate runner committed auction
  164 at revision 3. Publisher enqueue failed three times with
  `RedisClient::CannotConnectError`; backlog was 3, retry count 3, published
  count 0. Restoring Redis and rerunning the publisher acknowledged all three;
  backlog became 0 and worker jobs completed. The bid never rolled back.
- For auction 164 revision 4, an injected publisher SIGKILL occurred after a real
  Sidekiq enqueue and before PostgreSQL acknowledgment. The event stayed pending
  at attempts 0. Another publisher enqueued it again; two distinct real worker
  JIDs completed, one outbox event remained and the auction revision stayed 4.
- Two real PostgreSQL connections showed `SKIP LOCKED` prevents duplicate active
  claim of one row and permits another publisher to advance a different row.
  Focused outbox spec: 9 examples, zero failures, seed 31458, including a
  one-year publisher clock skew regression.
- With the final PostgreSQL-clock publisher restarted, stopped Redis again and
  committed auction 164 revision 5, event `9e4b0cd8…`. It stayed pending after
  four real failed attempts; Redis restoration led to acknowledgment on attempt
  five, a completed worker job and backlog zero. The bid price stayed 12,000.
- Sabotage A removed the atomic outbox call: 8 examples, 7 expected failures,
  including missing committed intent. Sabotage D inserted an event on replay:
  one-event spec failed with expected 3/got 4. Both temporary source changes
  were restored byte-identically. Sabotage B used the real Redis outage; C used
  the real publisher acknowledgment crash. Normal specs passed afterward.
- Full native `scripts/check` passed after the clock and timeout fixes:
  368 backend examples, zero failures; RuboCop 90 files/zero offenses;
  Brakeman zero warnings; Zeitwerk, frontend lint/format/types, 73 Vitest tests
  and production build passed. `bin/bundler-audit` reported no vulnerabilities.
- Real HTTP concurrent bidding, proxy bidding and sequential auction smoke
  scripts passed through Compose. A second independent Rails API on port 3002
  passed the multi-process idempotency smoke. The independent API A/Cable B
  verifier initially exposed an obsolete exactly-one-hint assertion: earlier
  lifecycle jobs produced duplicate current-revision hints. After updating the
  verifier to assert payload and stream isolation while tolerating duplicates,
  it passed with auction 186, revision 2 → hint/REST 3, plus malformed and
  disallowed-origin rejection. Web lint and format checks passed afterward.
- Multi-process closing smoke passed six scenarios with two API processes and
  the autonomous closer paused: soft-close arithmetic, stale closer discovery,
  bid/close race, two concurrent closers and expiry. The closer was restarted.
- `docker compose up --build --wait --wait-timeout 240` reported all eight
  services healthy. Real API Playwright passed 7/7 using system Chrome because
  the pinned browser CDN returned HTTP 403 in this location. Browser scenarios
  covered manual/proxy bidding, response loss, reconnect, soft close, lifecycle,
  responsive forms and autonomous winner notification.

### Limits and review

Redis data loss after outbox acknowledgment, exhausted Sidekiq retries, Cable
failure or a continuously connected stale browser can still lose a hint. REST
remains the recovery authority. Publisher retries can duplicate/reorder work;
no exactly-once, global-order, fixed-latency, throughput or production durability
claim is made. Poisoned pending rows require operator investigation. No Kafka,
projection or domain-event consumer was introduced. See the runbook and Phase 9
ExecPlan for the completed adversarial review. The review found and fixed a
host-clock retry/metric skew risk; a focused mutant that assigned SQL expressions
to typed model attributes failed and was replaced with explicit PostgreSQL
clock reads. CI now checks the publisher's one-shot command. The local browser
download was location-blocked (HTTP 403), so actual Playwright tests used
installed system Chrome. Hosted CI and production capacity were not verified.
Phase 10 has not begun.

Commits: `f2d59cd` implements the Phase 8 runtime/config/tests; documentation
completion is committed separately. The preceding `63edbb8` commit records the
pre-existing context migration and contains no Phase 8 product code.

## Phase 10 — Kafka

Status: COMPLETE — verified 2026-09-30. Phase 11 has not begun. The detailed
[ExecPlan and Evidence Index](plans/phase-10-execplan.md) hold commands, seeds,
event IDs, logs, failures and recovery observations.

### Implementation and boundary

The Phase 9 PostgreSQL transaction still commits auction mutation, public
revision and one outbox row before any transport work. New rows carry one
public-only domain snapshot and independent Kafka retry/acknowledgment fields;
the Sidekiq/Cable publisher and its acknowledgment remain unchanged. Historical
Phase 9 rows were marked Kafka-acknowledged without invented event content.
`rdkafka` 0.30.0 sends to the three-partition local topic
`hammerfall.auction-events.v1`, keyed by auction ID. The publisher waits for
broker delivery before PostgreSQL acknowledgment and retries failures with
persisted backoff. The `hammerfall.audit.v1` group validates exact v1 envelopes,
commits receipt and public audit entry together, then commits Kafka offset.
Duplicates are no-ops; gap/stale order is recorded; poison stops consumption
without an offset commit. [ADR-011](adr/011-kafka-domain-events.md) defines the
contract and [Kafka runbook](runbooks/kafka.md) the operator path. No Redis
projection or Phase 11 behavior was introduced.

### Actual failure and recovery evidence

- Compose built and started the single broker, topic initializer, publisher
  and consumer; an end-to-end auction at revision 3 produced three Kafka
  acknowledgments and three audit receipts. Topic metadata showed three
  partitions, replication factor one.
- Stopping Kafka did not stop a bid: auction 196 committed price 11,000 and
  revision 4 while Sidekiq acknowledged its hint and Kafka retained a pending
  row with `Rdkafka::RdkafkaError`. Broker restoration drained it at attempt 5
  and the audit group caught up.
- SIGKILL after broker delivery but before PostgreSQL acknowledgment left
  revision 5 pending. A retry produced two Kafka records with the same UUID;
  the audit group retained one receipt and one side effect. SIGKILL after the
  consumer database effect but before offset storage replayed revision 6 as a
  duplicate after restart, with one effect and unchanged price.
- A deliberately unsupported schema version at partition 1 offset 7 stopped
  the consumer. A valid revision 7 at offset 8, the auction bid and both
  transport acknowledgments continued while audit waited. An explicit offset
  reset after review let the valid event through. Replay from offset 0 caused
  duplicate no-ops and stopped again at the poison record. The consumer
  container was recreated with no restart policy after an initial container
  retained an obsolete restart setting during a live YAML edit.
- With Redis stopped, auction 224 reached revision 3 and Kafka published and
  audited all three events while Sidekiq acknowledgments stayed 0/3. Redis
  recovery drained those rows to 3/3. Kafka and Sidekiq share outbox row locks,
  so a slow Kafka send can briefly delay a hint enqueue without changing a bid.
- Sabotage A–D removed transactional event intent, skipped the delivery wait,
  bypassed receipt lookup and moved offset storage before database effect.
  Focused tests failed as intended. All sources were restored byte-identically
  and 19 focused examples then passed. Final review added event-classification
  and a two-connection duplicate-consumer race check; 22 focused examples pass.

### Regression, review and limits

`scripts/check` passed 381 backend examples, 98 RuboCop files, Brakeman with
zero warnings, Zeitwerk, frontend lint/format/types, 73 Vitest tests and a
Next production build. Compose Kafka smoke and native host listener worked.
Real Playwright passed 7/7; sequential, concurrent, proxy, two-process
idempotency and multi-process closing smoke passed. Bundler audit found no
vulnerabilities. Hosted CI was not run. The local broker is single-node,
plaintext and unbacked-up; no production capacity, latency, HA, TLS/ACL,
schema registry, alerting or exactly-once claim is made. Broker retention
bounds replay; poison skip is an explicit operator decision. Cable/Redis
post-acknowledgment loss and browser REST recovery limits remain. Phase 11 is
ready only as a separately requested phase, with Kafka event ordering and
retention limits carried into any projection design.

Commits: `874deb7` implements and tests the Kafka runtime, Compose topology,
CI smoke and event contract; documentation/evidence completion is committed
separately.

## Phase 11 — Redis Projection

Status: COMPLETE — verified 2026-09-30. Phase 12 has not begun. The
[ExecPlan](plans/phase-11-execplan.md) holds the detailed Evidence Index,
live campaign, sabotage outcomes and adversarial review.

### Implementation and boundary

The separate `hammerfall.projection.v1` Kafka group validates committed public
v1 snapshots, atomically writes a versioned Redis key per auction, then commits
its offset. Higher revisions replace older ones; equal public data is a
duplicate; lower revisions are stale; equal-revision conflicting data stops
the consumer. The key stores only public fields plus revision, event/source,
digest and freshness metadata. `GET /api/v1/auctions/:id/public-state` is an
explicit eventual read with Redis source/age or PostgreSQL fallback. Ordinary
GET and all commands remain PostgreSQL-backed. A manual PostgreSQL seed
rebuilds disposable keys. [ADR-012](adr/012-redis-public-projection.md) and the
[runbook](runbooks/redis-projection.md) define the policy and recovery.

### Failure and sabotage evidence

Live Compose delivery reached auction 226 revisions 3/10000 and 4/11000.
Duplicate and stale Kafka records left it at 4/11000. During Redis outage a
bid committed in PostgreSQL at 5/12000 and the eventual GET fell back; the
uncommitted event applied after restart. Deleting all 24 projection keys from
shared DB 0 and fully flushing isolated DB 15 left authoritative state intact.
The manual PostgreSQL rebuild seeded 181 auctions; replay did not regress the
seed. A real consumer exit after Redis write but before offset commit left
lag one; restart replayed a duplicate and cleared lag. Concurrent writes,
private-maximum exclusion and corrupt-key fallback were checked. Four
temporary sabotages each made the relevant stale, duplicate/conflict,
fallback or privacy tests fail; sources were restored and the projection suite
passed 8 examples. The retained local topic's Phase 10 poison event stopped
the earliest-offset projection group. Its local campaign offsets were reset
only after review, and PostgreSQL supplied current state.

### Final regression and runtime

The full backend suite passed 389 examples, 0 failures (seed 56291). RuboCop
inspected 101 files with no offenses; Brakeman found no warnings and
bundler-audit found no vulnerabilities in its checked database. Frontend
Vitest passed 73 tests; lint, formatting, types and production build passed.
Compose rebuilt successfully and all services became healthy. Redis, Kafka,
scheduler/publishers, Kafka/API, closer, concurrent/proxy bidding and pruning
smokes passed. Fresh auction 227 showed PostgreSQL and Redis at revision
3/10000, three broker-acknowledged outbox events, and both HTTP reads 200.
Real Playwright with system Chrome passed 7/7 browser scenarios, including
retry, Cable recovery, soft close and autonomous closing. Hosted CI itself
was not run; its API job now includes Redis for the integration spec.

Final review found no known serious Phase 11 correctness bug. The endpoint
can serve a valid stale key indefinitely; it has no synchronous freshness
or exactly-once claim. Kafka retention and historical rows prevent assuming
complete replay. Corrupt-key removal and full-loss rebuild require operators;
automated projection drift detection/repair awaits Phase 12. Local Redis/Kafka
provide no measured production capacity, fixed replay time or HA guarantee.
The demo API remains unauthenticated. Phase 12 is ready only for a separate
explicit request.

## Phase 12 — Reconciliation

Status: COMPLETE — verified 2026-10-01. Phase 13 has not started. The
[ExecPlan](plans/phase-12-execplan.md) indexes commands, live logs, failures,
sabotage and limits. [ADR-013](adr/013-bounded-reconciliation-scan-ownership.md)
and the [runbook](runbooks/projection-reconciliation.md) define scheduled
ownership and operations.

### Implementation and live campaign

The checker compares PostgreSQL public revision and the exact public v1
presenter fields against a validated Redis key. Missing and valid lower
revisions are seeded from PostgreSQL through the Phase 11 atomic Redis writer;
equal identical state is healthy. Equal conflicts, corrupt state and Redis
ahead of a fresh PostgreSQL row remain for review. The separate PostgreSQL
consistency sweep still reports authoritative anomalies read-only.

Live tests proved a Kafka N+1 projection cannot be regressed by repair from
snapshot N, while the opposite order converges. Two reconcilers safely
attempted the same repair, and a crash after Redis write retried harmlessly.
Redis outage left a bid committed at revision 3/price 10000 and recovery
seeded the missing key; PostgreSQL outage prevented speculative repair.
A 101-row test split into 100+1, and a Compose scan split 196 rows into
100+96. Four temporary sabotages of revision, conflict, authority and atomic
repair protections each failed the relevant test, then were restored.

An adversarial review found that fixed-size jobs alone did not bound
overlapping scheduled chains. PostgreSQL now holds one database-clock lease
per scan type, renewed by pages with token/cursor fencing. Two scheduler
instances cannot claim one chain; a repeated Sidekiq page cannot fork
successors. Completion releases the lease; a crash or lost handoff can delay
until ten-minute expiry, when a later tick restarts at ID zero. The lease
never participates in bidding. Cursor-fence sabotage failed its test and was
restored. Live Redis outage during scheduler enqueue released its claim
(`remaining_leases=0`); PostgreSQL outage made the one-shot scheduler fail
visibly. The scheduler-focused suite passed 20 examples before the broad run.

### Final regression and limits

The full backend suite passed 410 examples, 0 failures, 2 intentional live
Kafka pending (seed 28745). RuboCop inspected 108 files with no offenses;
Brakeman found zero warnings, bundler-audit no vulnerabilities, and Zeitwerk
passed. Frontend lint, format, typecheck and production build passed; Vitest
passed 73 tests. Compose rebuilt and all services became healthy. Health,
Redis/Kafka, one-shot scheduler, Kafka/API, concurrent/proxy bidding,
publishers and closer smokes passed. Real Playwright using system Chrome
passed 7/7 after the closer test waited for its asynchronous Cable hint.
The first full browser attempts showed a timing assertion race: REST had
already shown the closed winner before the Cable hint arrived. The isolated
closer scenario passed, and the final full suite passed with the bounded
wait. The Playwright CDN download returned a location-based 403, so the
installed system Chrome was used. Hosted CI itself was not run.

No known serious Phase 12 correctness bug remains. Valid stale projections
may persist until a successful scan; corrupt, conflicting and ahead states
need operator review. A lost handoff can delay a new scan until lease
expiry. Per-batch structured log counts are not exported Prometheus
counters, and no finite convergence bound, production capacity or HA claim
is made. The demo API remains unauthenticated. The separate Phase 0–11
hardening findings remain outside Phase 12; Phase 13 requires an explicit
request.

## Phase 12.5 — Correctness and production hardening (complete 2026-10-01)

The user explicitly opened a cross-phase repair pass after Phase 12. Session 1
reviewed the auction, proxy, deadline, idempotency, outbox, publishers,
consumers, Redis/reconciliation, lease, API, frontend retry, SQL, CI and
security defaults. It repaired shared semantic validation of public snapshots,
new outbox occurrence timestamps, model readonly event fields, lease expiry
after a conflicting row-lock wait, SQL domain snapshot shape, and production
host allowlisting. No Phase 13 work began. The active
[ExecPlan](plans/phase-12-5-hardening-execplan.md) contains classified findings,
deferred decisions and the Evidence Index.

Focused checks: 44 real PostgreSQL/Redis integration examples passed on an
isolated Redis DB (seed 17640), 78 adjacent auction/projection examples passed
(seed 22605), 12 changed Ruby files passed RuboCop and Zeitwerk passed. A
production config boot admitted an explicit host and rejected an empty host
list. One earlier DB 0 lease-spec run collided with the running development
projection consumer; isolated DB 1 tests passed without weakening assertions.
Session 2 reproduced publisher cross-path row exclusion in both directions
with real PostgreSQL. A controlled Kafka delay left its database backend idle
inside the open transaction; Sidekiq skipped the locked row and delivered after
Kafka committed. A live broker failure persisted Kafka retry state, then a real
broker delivery was acknowledged. `SystemExit` before enqueue and an actual
PostgreSQL CHECK rejection after fake Sidekiq acceptance left work retryable;
the latter duplicated the job on retry without duplicating event identity.
The current transaction-held design was retained because the cost is bounded
to one in-flight row/connection per publisher process and no load evidence yet
justifies an expiry/fencing state machine. This is an explicit operational
tradeoff, not a capacity claim.

Session 2 also deferred HMAC conversion to the security phase because retained
unversioned SHA-256 rows, multi-instance secret distribution and rotation need
a replay-preserving rollout. The lack of a pre-parse body limit remains a public
ingress blocker; a Content-Length-only patch would miss streamed requests.
The publisher configuration defaults now appear in `.env.example`. Focused
verification passed: 18 Kafka outbox examples including real broker failure and
recovery, 13 transactional outbox examples, 51 idempotency examples, and changed
Ruby lint. An ack-on-Kafka-failure sabotage failed its safety test and was
restored. Full regression, browser/runtime, security/build, hosted CI and final
documentation review remain for the next Phase 12.5 session. This is a second
checkpoint, not phase completion.

Finalization ran the complete backend suite after a new deadline invariant fix:
424 examples, 0 failures and 3 intentionally gated live Kafka examples (seed
19056). The three gated tests were run separately against local Kafka and
passed (seed 43552). RuboCop passed on 112 files, Brakeman reported zero
warnings/errors, Zeitwerk passed, and bundler-audit found no vulnerabilities.
Frontend lint, format, types, 73 Vitest tests and production build passed.

The final adversarial review found a missing pure deadline relation:
`starts_at < original_ends_at` was implied by ordinary create/edit commands
but not by shared public validation or SQL. A malformed Kafka/Redis snapshot
with original end at start could pass. Model, shared public validator and a new
PostgreSQL CHECK now enforce `starts_at < original_ends_at <= ends_at`.
Focused auction/SQL/Kafka/Redis tests passed 127 examples before the final
full regression; both local development and test databases had no violating
rows before migration.

Compose built and reported all relevant services healthy. Existing API/Redis/
Kafka/publisher/scheduler/closer/concurrent/proxy/pruning smokes passed; Kafka
smoke confirmed all three events acknowledged and consumed. Two independent
Rails processes passed the idempotency smoke, and cross-process Cable delivery
matched the REST revision. Real Playwright with installed Chrome passed 7/7
before and after the final deadline fix, including response-loss replay,
realtime recovery and autonomous closer. Hosted GitHub Actions was pending at
that checkpoint; subsequent verification follows.

The finalization candidate `390b92f` was pushed. Its hosted
[run 36840930691](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36840930691)
passed web, but GitHub's API service-container creation failed before checkout
with Docker exit 125 and the Compose job's combined browser setup exited 243.
The API workflow switched to the same Compose PostgreSQL/Redis services that
worked locally; Compose browser setup was split and changed to installed
runner Chrome. The next
[run 36841587172](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36841587172)
passed web and advanced the API to Brakeman. Its `--ensure-latest` gate exited
5 because the pinned 8.0.6 had been superseded by 8.1.0. Compose passed the
smokes, but host `npm ci` after stack startup still exited 243. The lockfile
was updated to Brakeman 8.1.0, and host browser dependencies were installed
before the Compose build. An isolated local Compose DB/Redis startup and Rails
`db:prepare zeitwerk:check` passed; Brakeman 8.1.0 found zero warnings and
bundler-audit found no vulnerabilities. Public GitHub annotations did not
expose the exact npm error beyond exit 243.

Commit `11358387bf197e776e4698a70bf9373190bc672f` passed all hosted
[CI jobs in run 36844131696](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36844131696):
API, web and Compose completed successfully, including backend RSpec, frontend
production build, full stack smoke and real browser scenarios. Phase 12.5 is
complete; no Phase 13 work began. Publisher lock/connection occupancy, absent
whole-cycle network bound, unkeyed idempotency digest privacy, and pre-parse
body limit remain explicitly documented future work. The demo is not
public-production-ready.
