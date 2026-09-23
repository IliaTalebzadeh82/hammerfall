# Engineering journal

## 2026-09-23 — Keep foundation capabilities honest

The master plan specifies RSpec, while Rails' default testing scaffold uses
Minitest. The app was generated without that scaffold and rspec-rails was added.
Optional Rails adapters and deployment tools were excluded because installing
future infrastructure now would obscure Phase 0's actual dependencies.

Rails' built-in health endpoint is deliberately liveness-only. PostgreSQL
readiness and a real ActiveRecord test connection are checked separately; a green
`/up` response must never be used to claim database or auction correctness.

## Frontend generator defaults needed verification

The current Next generator still selected deprecated ESLint 9. Upgrading to 10
produced incompatible peer ranges in React/accessibility plugins. The final
foundation uses Next-supported Biome with React/Next recommended lint rules and
formatting. The latest Babel React test plugin also conflicted with shadcn's
Babel dependencies; using its SWC counterpart resolved that dependency boundary.
No force/legacy-peer-deps flags or disabled checks were used in the final setup.

## Test environment isolation in containers

The development API container explicitly exports RAILS_ENV=development. Running
RSpec without an override correctly tripped the test-environment guard. Container
instructions now pass `-e RAILS_ENV=test`, and check scripts explicitly select the
test environment for specs. The guard remains active to protect other databases.
