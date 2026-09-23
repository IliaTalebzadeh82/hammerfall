# Progress

## Phase 0 — Repository Foundation

Status: COMPLETE

Verified on 2026-09-23. Phase 1 has **not** started. The master specification is
unchanged. Only Phase 0 is marked complete.

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
