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
not backend connectivity; the Phase 0 starting page does not call Rails.

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
schema changes and `RAILS_ENV=test bin/rails db:prepare` before specs. Phase 0 has
no domain migrations; database preparation creates Rails metadata only.

CI executes equivalent checks plus a container smoke test. A local build does not
prove a remote GitHub Actions run succeeded.

## Dependency updates

Commit Gemfile.lock and package-lock.json together with manifest changes. Use
`bundle install` in apps/api and `npm install` in apps/web. There is no root npm
workspace because only one JavaScript application exists. Use the shadcn CLI in
apps/web to add primitives when needed, rather than copying arbitrary components.
