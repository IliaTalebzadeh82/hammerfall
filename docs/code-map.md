# Code map

Phase 0 has no bidding or auction workflow. The map below describes only the
foundation being scaffolded; progress.md records when verification is complete.

## API liveness

`apps/api/config/routes.rb` → Rails built-in health controller → `/up`.
Request coverage: `apps/api/spec/requests/health_spec.rb`.

## Persistence foundation

`apps/api/config/database.yml` → PostgreSQL via ActiveRecord.
`apps/api/app/models/application_record.rb` is the abstract model base.
There are no business tables or migrations.

## Starting page

`apps/web/src/app/layout.tsx` → `apps/web/src/app/page.tsx` → shadcn/ui primitives
in `apps/web/src/components/ui`. Global styles: `apps/web/src/app/globals.css`.
Coverage: `apps/web/src/app/page.test.tsx`.

## Development and verification

`docker-compose.yml` → development Dockerfiles in `infrastructure/`.
`scripts/check` → per-app lint, test, type, build, and database checks.
`.github/workflows/ci.yml` → the corresponding CI jobs.
