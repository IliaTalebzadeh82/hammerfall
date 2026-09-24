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

## Phase 2 — Lock before deciding, not just before writing

Phase 1's reload and savepoint preserved atomic writes but allowed competing
read/check/write decisions. Phase 2 moves the serialization point to the auction
row, before status, time, minimum and sequence decisions. Lifecycle actions must
use the same protocol: otherwise close can compute a winner before waiting on a
later UPDATE and persist a stale winner after a bid commits.

The initial removal of all three command locks during mutation verification produced
five failures in nine PostgreSQL examples: stale acceptance/deadlock, duplicate ordering,
expired-window acceptance, cancellation followed by an accepted bid, and closure
with a missing winner. The mutation's deadlock came from inserting a child before
locking its parent: the foreign-key key-share wait and competing unique-sequence
insertion formed a cycle. Acquiring the auction lock first prevents that competing
write pattern. No broad retry was added to hide these failures.

The concurrency suite disables transactional fixtures only for its own group.
Tests commit owned data and hold distinct PostgreSQL connections, using Queue
barriers and pg_blocking_pids rather than sleeps to assume a race occurred.
A short polling sleep only yields while checking an actual database wait. The
many-contender test works with the existing pool of three, so not every contender
holds a connection at once. Separate backend PIDs prove independent sessions.

Early cleanup tried destroying a shared User object whose inverse bid association
had been populated in workers. That cached association caused deletion-restriction
errors even after SQL cleanup. Workers now load their own model instances and
cleanup targets owned IDs. The clock-wait test uses ends_at + one second because
Rails travel_to rounds to seconds while the stored end can retain microseconds.

Brakeman flagged interpolation of the internal pagination column as possible SQL
injection. The column was chosen only by code, but using Arel's greater-than
predicate removes raw SQL interpolation and keeps the existing scanner clean.
The API explicitly replaces bid-history after_id with after_sequence; other list
cursors remain unchanged. No scanner suppressions or dependency changes were needed.

The final barrier also holds two checked-out connections before releasing either
bidder, removing any dependence on checkout scheduling for session independence.
With this barrier, seeds 1–20 passed all nine examples each. A second mutation run
loaded the unlocked model only in the test process (leaving live API code intact):
seed 43814 failed seven of nine examples. Restoring normal loading passed the full
178-example suite natively and in Docker. These are bounded correctness tests,
not stress testing or a latency/throughput measurement.
