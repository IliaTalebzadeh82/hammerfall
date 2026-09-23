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

Verified on 2026-09-24. Phase 2 has **not** started. Phase 0 commits and frontend
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
