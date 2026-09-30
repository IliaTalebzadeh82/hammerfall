# Running locally

## Container development

Requirements: Docker Engine with Compose v2+ (verified with Engine 29.8.1 and
Compose 5.5.1). Commands below run from the repository root.

```sh
cp .env.example .env
docker compose config --quiet
docker compose up --build --wait
```

Frontend: http://localhost:3000. API liveness: http://localhost:3001/up.
PostgreSQL: localhost:5432. Ports bind only to loopback. Change `WEB_PORT`,
`API_PORT`, or `PGPORT` in `.env` if occupied. API containers always connect to
`db:5432`; the published PGPORT is only for native clients.

Containers run as non-root users. On Linux, set `LOCAL_UID` and `LOCAL_GID` in
`.env` to your `id -u` and `id -g` values before building if they differ from 1000.

Source directories are bind mounted so edits reload. Dependencies and generated
Next.js/Rails temporary files use named volumes. On startup, Bundler/npm reconcile
the installed dependencies with committed lockfiles. The frontend reinstalls only
when its package manifest or lockfile changes; a checksum marker in node_modules
keeps ordinary restarts fast. Rebuild after changing
Dockerfiles or runtime versions. No production image or deployment is provided.

```sh
docker compose logs -f
docker compose exec -e RAILS_ENV=test api bundle exec rspec
docker compose exec web npm test
docker compose stop
docker compose down
```

Before the first container RSpec run, create its isolated test database:

```sh
docker compose exec -e RAILS_ENV=test api bin/rails db:prepare
```

`down` preserves database and dependency volumes. `down --volumes` **deletes local
database data**; do not use it as routine shutdown. Changing POSTGRES credentials
in `.env` does not change an already-initialized database user's password.

`/up` is Rails liveness, not a database query. Compose waits for PostgreSQL readiness
before Rails starts, and Rails prepares its database. The RSpec integration check
asserts a real connection to `hammerfall_test`. Frontend health confirms HTTP 200,
not backend connectivity; browser API failures have their own retryable error states.

## Native apps with container PostgreSQL

Use Ruby 4.0.6, Bundler 4.0.19, Node 24.20.0, and npm. Version files are provided
for mise and other version managers. Native gem installation needs a compiler and
PostgreSQL client development headers if a precompiled pg gem is unavailable.

```sh
cp .env.example .env # only on first setup; preserve your existing settings
set -a
. ./.env
set +a
docker compose up -d --wait db
(cd apps/api && bundle install && bin/rails db:prepare)
(cd apps/web && npm ci)
```

Run in separate terminals with the `.env` variables exported:

```sh
cd apps/api
bin/rails server -p "${API_PORT:-3001}"
```

```sh
cd apps/web
npm run dev -- --port "${WEB_PORT:-3000}"
```

Do not run container apps and native apps on the same ports. Production uses an
explicit `DATABASE_URL` and `SECRET_KEY_BASE`; it is outside this phase's scope.
Avoid exporting DATABASE_URL in native development/test: it overrides the isolated
named databases in database.yml.

## Checks and formatting

```sh
./scripts/check
(cd apps/api && bin/bundler-audit)
(cd apps/api && bundle exec rubocop -a)
(cd apps/web && npm run format)
```

The check script reads root `.env`, validates Compose, checks Ruby lint/security and
autoloading, prepares the test database, runs RSpec, then frontend lint, formatting,
types, Vitest, and a production build. Run `bin/rails db:prepare` for development
schema changes and `RAILS_ENV=test bin/rails db:prepare` before specs. Phase 1 has a reversible migration for users, auctions, and bids; current schema
is committed. Never roll back a populated development database just to test a migration.

CI executes equivalent checks plus a container smoke test. A local build does not
prove a remote GitHub Actions run succeeded.

## Dependency updates

Commit Gemfile.lock and package-lock.json together with manifest changes. Use
`bundle install` in apps/api and `npm install` in apps/web. There is no root npm
workspace because only one JavaScript application exists. Use the shadcn CLI in
apps/web to add primitives when needed, rather than copying arbitrary components.

## Phase 1 demo and API verification

```sh
docker compose exec api bin/rails db:seed
docker compose exec -T -e API_BASE_URL=http://127.0.0.1:3000 api ruby < scripts/smoke-api
```

Seeds populate only an empty development domain with 3 users, scheduled/active/
closed auctions, and 4 bids. A rerun or a database with existing domain records is
left unchanged. The active seed's window lasts seven days from its first creation;
seeds never reopen or refresh old auctions. The historical closed example uses
explicit historical fixture SQL before normal closure; creation times are insertion metadata.
No test/production data is seeded.

The smoke script creates its own labelled records, exercises the real JSON API,
waits about 65 seconds for the deadline, and leaves its closed auction for
inspection. Native Ruby users can run `./scripts/smoke-api`; set API_BASE_URL if the
API port differs from 3001. API details: [api.md](api.md).

The API deliberately uses client-supplied bidder IDs without authentication. Keep
it local. Concurrent bidding, race-safe closure and idempotency are implemented; authentication remains future work.


## Phase 2 migration and concurrency verification

The sequence migration backfills existing bids by ID within each auction and adds
NOT NULL/positive/unique constraints. Stop old API writers before this maintenance
migration; do not mix old bid-writing code with the new schema. For an existing
checkout: `docker compose stop api`, migrate using the new code (native
`bin/rails db:migrate` with PG variables, or a one-off Compose API command), then
`docker compose up --build --wait`. No development data rollback is required.
Rollback/reapply tests belong in the isolated test database.

Run `bundle exec rspec spec/integration/concurrent_bidding_spec.rb` in apps/api.
Only this group disables transactional fixtures. It uses committed owned records,
separate database sessions, Queue barriers and pg_blocking_pids observations.
Default pool size 3 permits a holder and two workers; 12 contenders queue for
connections after their start barrier. Cleanup deletes only each example's records.
For repetition, run the group with `--seed` values 1 through 20, stopping on failure.

`./scripts/smoke-concurrent-bids` checks live HTTP contention and retains labelled
rows. To exercise existing independent Rails processes, pass comma-separated
`API_BASE_URLS`. Neither the test nor the script measures capacity.

## Phase 3 proxy verification and migration

Run `bundle exec rspec spec/models/maximum_bid_spec.rb spec/requests/maximum_bids_spec.rb`
and both `spec/integration/concurrent*_spec.rb` groups from apps/api with the
normal PG environment. Transactional wrappers stay enabled outside those groups.
Run `./scripts/smoke-proxy-bidding` against a healthy API; optional API_BASE_URLS
routes its final race across two independent processes. Labelled demo rows remain.

The new migration backfills current_leader_id from the last Phase 2 visible sequence
and existing Bid.origin as manual. Stop old writers for maintenance deployment.
Test rollback/reapply on a test database with pre-proxy history. Downgrade refuses
when MaximumBid rows exist, preventing silent destruction of binding private
commitments. An explicit preservation/migration plan is required in that case.

If a registry lookup fails but the verified development image is cached,
`docker compose up --no-build --wait` can run the bind-mounted current code with
unchanged dependencies. This verifies runtime behavior; it does not prove that a
fresh image can be built while the registry remains unavailable.

## Phase 4 closer process

`docker compose up --build --wait` now starts `auction-closer` alongside api/web/db.
It runs the same Rails image/application against the same PostgreSQL database.
No Redis or queue is involved. Override AUCTION_CLOSER_INTERVAL (positive seconds,
default 1) and AUCTION_CLOSER_BATCH_SIZE (1..10000, default 100) in the environment.
A poll interval is not a promise that status changes within that interval.

Native, after exporting the usual PG environment:

```sh
cd apps/api
bin/auction_closer          # continuous; SIGTERM/SIGINT finishes current work then stops
bin/auction_closer --once   # one bounded discovery pass
```

The executable defaults PGOPTIONS to lock_timeout=5s and statement_timeout=10s;
set PGOPTIONS explicitly to override. Long waits become logged transient failures,
with another discovery attempt on a later pass. A one-shot sweep with transient
failures exits unsuccessfully. Unknown per-auction errors log
auction ID/error class and exit; Compose uses restart:on-failure. Logs deliberately
omit SQL/exception messages that could contain private data. This is basic process
operation, not a health/freshness SLA or observability platform.

```sh
docker compose logs --tail 50 auction-closer
docker compose stop auction-closer
docker compose run --rm auction-closer bin/auction_closer --once
docker compose start auction-closer
```

Stopping the closer does not reopen deadlines. Late bid/max commands still reject
auction_ended while a row may remain active. They do not lazily mutate closure.

Maintenance rollout: stop API writers and closers, migrate, deploy matching code,
then restart. Phase 4 backfills original_ends_at=ends_at and estimates old closed_at
as GREATEST(updated_at,ends_at). Rollback/reapply was tested with existing Phase 1–3
records. A downgrade refuses detectable live extensions/closure timestamps because
removing columns loses this new history. Export and plan preservation before a live
downgrade; do not reset the development database. Demo seeds now use an explicit
historical fixture import for the closed example; production methods have no at:
clock override. Existing seed data is still never overwritten.

The sequential HTTP smoke now waits about 65 seconds (or longer if an unexpectedly
slow run enters the extension window). For Phase 4 demonstrations, start a second
Rails API at port 3002, then from the root with native PG variables exported:

```sh
docker compose stop auction-closer
API_BASE_URLS=http://127.0.0.1:3001,http://127.0.0.1:3002 ruby scripts/smoke-closing
docker compose start auction-closer
```

The development-only script retains labelled rows. It uses fixture SQL to arrange
some deadlines, actual DB time for decisions, real HTTP calls across both APIs,
and two independent Ruby/Rails closer processes. Its stale-candidate example holds
an accepted extension uncommitted until another process discovers the old due row
and waits for its lock. It does not mock production clocks or locks. Restart the
normal closer even if the demonstration fails. `scripts/smoke-concurrent-bids` and
`scripts/smoke-proxy-bidding` remain compatible with API_BASE_URLS.

Tests: the full backend suite includes a roughly 32-second real repeated-extension
case. `bundle exec rspec --tag '~slow'` skips only that case for short development
feedback; full verification must include it. Run the concurrent_* specs
serially against the test database (with different seeds for repetitions), never
parallel full suites sharing that database.

## Phase 5 keys and retention

Both bid and maximum HTTP mutations now require Idempotency-Key. Existing scripts
supply fresh keys for distinct commands. For retries, keep the same key and exact
semantic payload; check Idempotency-Replayed: true on a retained matching retry.
Lifecycle/closer operations remain independent of client keys. See api.md and ADR-006.

Default IDEMPOTENCY_RETENTION_DAYS=7 (integer 1..365) controls prune eligibility from
claim transaction start. Existing records retain their original expiry; changing
configuration affects new claims only. Expired-but-present keys still replay/conflict.
Only physical prune allows reuse. Run one bounded batch manually:

```sh
cd apps/api
bin/rails idempotency:prune
IDEMPOTENCY_PRUNE_BATCH_SIZE=100 bin/rails idempotency:prune
# Container equivalent:
docker compose exec -T api bin/rails idempotency:prune
```

Batch default is 1000, maximum 10000. The task uses database time and skips locked
rows. It is not automatically scheduled. Keep records for at least the supported
client retry horizon; after pruning the old identity can execute again. Monitor
storage/cleanup operationally before production. A populated-table downgrade refuses
to discard retained outcomes; preserve them or deliberately expire/prune under an
approved retention policy before downgrade. Do not drop/reset existing domain data.

With a second Rails API running at localhost:3002 and normal PG variables exported:

```sh
API_BASE_URLS=http://127.0.0.1:3001,http://127.0.0.1:3002 ruby scripts/smoke-idempotency
```

This development-only script uses real concurrent HTTP requests, compares stored
state and exact response snapshots, and retains labelled rows. It covers plain
manual/proxy/new-max/increase duplicates, conflicts, lost responses after price and
leader changes, replay after closure, and rejection history. Some expiry fixtures
use explicit setup SQL; production decisions still use the real DB clock.

Run all four concurrent_* suites repeatedly, serially against the test database.
Idempotency adds no process-local lock or new service. The existing closer remains
a separate Rails process role and needs no Idempotency-Key.

## Phase 6 browser frontend

Open http://localhost:3000/auctions. Choose a real demo user in the header; the
selector is explicitly unauthenticated. Browse a detail page, enter EUR strings,
and submit a manual or binding private maximum bid. The API still decides acceptance,
leadership, extensions and closure. Detail pages now subscribe to public auction
invalidations. Initial load, subscription confirmation/reconfirmation, visible-tab
return, command completion, explicit refresh and countdown expiry request REST state.

All browser API calls use `/api/v1`. `next.config.ts` transparently rewrites to
API_ORIGIN: native default http://127.0.0.1:3001; Compose sets http://api:3000.
For another native API port export API_ORIGIN before starting Next. Restart after
changes; production builds capture rewrite configuration. Only loopback is added
to Next's allowed development origins, and Rails development allows the Compose
`api` host. No credentials belong in this URL or NEXT_PUBLIC variables.

The existing small development seed remains unchanged: three demo users and
scheduled/active/closed examples are sufficient to start browsing. It skips an
existing domain and never refreshes expired auctions. Browser scenarios create
fresh labelled fixtures through the API instead of resetting your data. Lifecycle
activation remains explicit; the frontend does not add admin controls.

Pending command recovery uses sessionStorage; selecting a demo actor uses
localStorage. If a response is lost, keep the saved attempt and use Retry safely.
Reloading or navigating within the same tab preserves it. Refresh alone cannot
confirm the command outcome. Private maximum input may remain temporarily in the
caller's pending session record until terminal resolution/abandonment/tab cleanup.
Do not copy this storage into logs or bug reports. The client retry window is one
hour; it is not indefinite server retention. See frontend.md and ADR-007.

Browser verification against the running local Compose stack:

```sh
cd apps/web
npm ci
npx playwright install chromium
npm run test:e2e
# Optional compatible installed-browser fallback when downloads are unavailable:
PLAYWRIGHT_CHROMIUM_EXECUTABLE=/opt/google/chrome/chrome npm run test:e2e
```

Set E2E_BASE_URL for another frontend port. The tests exercise real mutations and
retain labelled records, so use only a local demo/disposable environment. They
cover browsing, actor selection, manual/max bidding, stale rejection, a committed
response deliberately dropped before reload/retry, zero/closure, lifecycle states,
and 390/768/1440 layouts. Screenshots live in ignored apps/web/test-results; no
private traces or network payload reports are enabled. GitHub's Compose job installs
Chromium and runs the same scenarios. A local run is not evidence that hosted CI ran.

The complete native check remains scripts/check. Frontend-only: npm test, lint,
format:check, typecheck and build. A production smoke can use `npm run build` then
`npm run start -- --hostname 127.0.0.1 --port 3100` while Rails remains running.
The next build reads API_ORIGIN; it requires no database access to generate pages.

## Phase 7 Cable verification

Normal development/production use the PostgreSQL adapter; tests use the isolated
Cable test adapter. `CABLE_ALLOWED_ORIGINS` is a comma-separated exact origin list.
Development defaults allow localhost/127.0.0.1 port 3000; production defaults deny
all origins. Add the actual frontend origin for another port. Do not disable origin
checks. `NEXT_PUBLIC_CABLE_URL` is public build-time configuration (Compose defaults
to ws://localhost:3001/cable); production needs WSS and a proxy supporting WebSocket
upgrade, or the client's default same-origin `/cable` route. Rebuild after changing
NEXT_PUBLIC variables. Never put credentials in the URL.

For a cross-process proof, keep Compose API A on 3001 and start an independent B:

```sh
# Repository root; load local PG environment without printing credentials.
set -a
. .env
set +a
(cd apps/api && bin/rails server -b 127.0.0.1 -p 3002 -P /tmp/hammerfall-cable-b.pid)
# In another shell, from repository root:
API_BASE_URLS=http://127.0.0.1:3001,http://127.0.0.1:3002 \
  PLAYWRIGHT_CHROMIUM_EXECUTABLE=/opt/google/chrome/chrome \
  node apps/web/scripts/verify-realtime.mjs
```

The script writes through A, subscribes through B, compares the exact notification
and REST revision, tests stream isolation, malformed IDs and rejected origins.
It retains labelled demo fixtures. Browser tests additionally cover two users,
proxy contests, 90-second extension, ordinary closer publication and missed-message
reconnect recovery. The closure scenario intentionally waits for a real deadline.
For full browser tests routed through B, build/start a frontend with
NEXT_PUBLIC_CABLE_URL=ws://127.0.0.1:3002/cable and an allowed frontend origin.
Cable defaults to two workers; each Rails listener also uses a dedicated PostgreSQL
connection outside the ordinary pool. Size total connection capacity across API and
closer processes before increasing workers. This is not a production sizing result.

## Phase 9 outbox, Redis, Sidekiq and sweeps

Compose now starts Redis (loopback port `REDIS_PORT`, default 6379), a two-thread
Sidekiq process, `outbox-publisher` and a separate `reconciliation-scheduler` alongside the existing
API, web, database and authoritative closer. Redis uses a named local volume with
append-only persistence; it is not a backup. Native processes use `REDIS_URL`
(default `redis://127.0.0.1:6379/0`); Compose supplies `redis://redis:6379/0`.
The API does not require Redis to boot or accept bids.

```sh
docker compose up --build --wait
docker compose exec -T redis redis-cli ping
docker compose ps sidekiq outbox-publisher reconciliation-scheduler
docker compose exec -T api bin/rails runner 'p OutboxPublisher.new.backlog_metrics'
docker compose exec -T reconciliation-scheduler bin/reconciliation_scheduler --once
docker compose logs --tail 100 --no-color outbox-publisher sidekiq reconciliation-scheduler api
```

`RECONCILIATION_INTERVAL` defaults to 60 seconds (minimum 5). Each sweep checks
bounded groups of PostgreSQL auctions against their latest accepted Bid and logs
drift without repairs. `--once` fails visibly when Redis cannot accept a job. The
Sidekiq `notifications` and `maintenance` queues retry job failures five times;
the Dead set needs operator inspection. Use the [runbook](runbooks/sidekiq-redis.md)
for queue counts, outage and recovery. Do not expose an unauthenticated Sidekiq
Web UI or mistake queue drain for guaranteed notification delivery.

The outbox row commits with each public revision; the independent publisher
enqueues it later. `AuctionChangedJob` reads current revision and broadcasts the
same public Cable hint through PostgreSQL.
The existing independent API A/Cable B script still proves cross-process delivery
with Sidekiq running. Redis outage before enqueue leaves committed rows pending;
restoring Redis lets the publisher retry. Browser REST recovery still applies.
No Kafka exists in Phase 9. See the [runbook](runbooks/sidekiq-redis.md).
