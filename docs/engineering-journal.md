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

## 2026-09-24 — Phase 1 exposed a JSON parser incompatibility

The first real JSON request specs returned 400 even for valid bodies. A direct
ActiveSupport::JSON.decode call showed Rails 8.1.3.1 invoking JSON.parse with a
positional options hash, while JSON 3.0.2 accepts keyword options only. Phase 0's
health and database checks did not exercise request JSON parsing.

Constrained the json gem to the compatible 2.x line (locked at 2.21.2), without
patching Rails or weakening request parsing. Valid/invalid JSON request tests now
pass. The Docker image was rebuilt and actual HTTP mutations verified afterward.
Revisit the constraint when the Rails decoder supports the new parser interface.

## Nested transactions need explicit rollback scope

Reviewing the bid/price invariant exposed a Rails transaction detail: a transaction
block normally joins an existing transaction. If an outer operation catches an
exception from the price write, the earlier bid insertion can survive. A focused
regression test reproduced one persisted bid after the failure.

place_bid! now requests a new transaction/savepoint. The same test confirms no bid
survives the rescued failure. This is atomic rollback scope, not locking or
serialization. Simultaneous calls remain explicitly unsafe in Phase 1.
