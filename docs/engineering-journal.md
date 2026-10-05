# Engineering journal

## 2026-10-02 — Phase 17 routing needed an explicit distribution proof

Two healthy Rails containers behind nginx did not initially mean two Rails
processes received requests: auto-sized nginx workers each favored the first
upstream at low request volume. A one-worker local proxy then alternated six
GETs and delivered the command races to both replicas. Rails host authorization
also needed the internal proxy host for the verifier. The first verifier had
two incorrect assumptions about initial revision and private-key matching;
its direct SQL count later needed an uncached read because the runner's query
cache does not see writes from other HTTP processes. The retained runs and
limits are in [Session 1](multi-instance/session-1.md).

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

## Phase 3 — One transaction for private permission and public competition

The decision table in ADR-004 was written before the resolver. Private MaximumBid
and public Bid are different facts. An explicit leader avoids accidentally using
highest-amount/ID ordering when equal-ceiling contests emit equal-price rows.
A durable priority assigned on each raise prevents an old lower ceiling from
claiming seniority at a new higher ceiling.

The pairwise resolver depends on a settled-state invariant: previous losing maxima
are exhausted at/below public price or lose an equal-ceiling priority tie. Therefore
only the incoming bidder and current leader compete. Visible loser ceiling precedes
winner amount; this prevents the nonsensical 350 then 300 history. At most two
visible rows are emitted, with final price/leader and private state in one commit.

Initial implementation retained an unsaved validation-only Bid in the auction's
association target and implicitly revalidated private instructions during the
auction save using the wrong validation context. Rails correctly rejected those
parent saves. The manual candidate is now a standalone validation object; MaximumBid
writes are explicitly validated/saved, with parent autosave and implicit validation
disabled for that association. Tests were retained and passed after the fix.

Capturing real debug logs confirmed Rails' parameter filter also filters ActiveRecord
SQL binds and model inspection for maximum_amount/priority_sequence/origin. Public
presenters and amount-free maximum acknowledgements are independently tested. This
does not supply authentication or hide amounts that legitimately become visible bids.

The unlocked test-process mutation failed nine of ten proxy concurrency examples;
normal code passed twenty combined manual/proxy runs (380 examples). No sabotage
was written into application source. Real SQL failure after two visible inserts
proved rollback of private state, priority, history, price and leader, including
an outer transaction that handled the error.

A bounded local lock observation used sql.active_record monotonic notifications:
interval from completion of SELECT FOR UPDATE to completion of COMMIT, including
its query comment. Two warmups and twenty samples per case compared a manual-only
challenge (one visible insert) with an automatic counter (two visible inserts).
Observed median: 19.294 ms manual, 23.894 ms proxy; ranges 12.700–32.287 and
13.548–30.760 ms respectively. This local run had other development activity and
is not an isolated benchmark; it suggests extra lock-held work (~4.6 ms median
here), not a stable latency, capacity estimate or throughput promise. Sample-owned
rows were removed; user/demo rows were untouched. Phase 14/15 own proper measurement.

Docker Hub returned HTTP 403 for ruby:4.0.6-slim manifest resolution during a
Compose rebuild. The unchanged cached API runtime successfully started with current
bind-mounted source and passed the full 233-example suite and live proxy tests.
The frontend image build completed. No runtime version, lockfile or security check
was changed to bypass the registry failure. After resuming later, a normal `docker compose up --build --wait` retry resolved
the registry metadata, built both images with cached layers, and left all services
healthy. The temporary registry failure is resolved; no no-cache build is claimed.

Final review found a subtle eligibility hole in allowing noncompetitive increases:
Alice max 300, Bob max 400, Alice manually bids 500, then Bob raises to exactly
500 without becoming leader. If Alice later protects her existing 500, Bob would
hold an earlier equal private priority while Alice stayed leader. We reject the
nonleader's noncompetitive increase before assigning priority. All new/increased
ceilings must cover the leader's own price or strictly exceed another leader's
price; same-value repeats still no-op after lifecycle/time validation. A dedicated
regression proves no dormant equal-price priority is created. This tightens the
initial policy and preserves the resolver's settled-state and equal-ceiling rules.

## Phase 4 — database clock, connection leases and meaningful timing tests

Moved all production deadline decisions to one uncached PostgreSQL clock_timestamp()
after the locking reload. Removed the old at: override and Rails time-travel wrapper;
expired fixtures now explicitly arrange stored deadlines, and concurrency tests
wait on actual DB time. Original/closure timestamps and atomic +90 extension belong
to the auction transaction, not the number of proxy rows. Closer discovery is only
a hint; the domain remains the finalizer.

The first clock helper used ApplicationRecord.connection inside worker checkouts.
That promoted temporary leases to permanent ones and exhausted the default three-
connection pool in the many-contender tests. Using connection_pool.with_connection
and connection.uncached fixed it; the existing contention tests caught the issue.
An accidentally overlapping pair of test runs also produced shared-test-database
interference; both were stopped and all reported passing suites ran serially.

The first transaction-time sabotage also froze the test's waiting helper because
it used the same production AuctionClock. That produced timeouts rather than the
intended bad acceptance. The helper now observes raw, uncached DB wall time
independently. Rerunning the mutation then proved the actual fault: both pre-expiry
transactions were incorrectly accepted after waiting past expiry. The normal code
rejected both. Removing only the closer's row lock separately failed both stale
candidate examples and duplicate timestamp finality. Mutations lived in /tmp and
were loaded only in their RSpec processes; production source stayed intact.

Legacy closed_at backfill is an estimate, never retroactive DB-clock evidence.
A pre-Phase-4 development snapshot matched byte-for-byte before and after rollback/
reapply across all old columns (48 users, 22 auctions, 52 bids, 14 private maxima).
The downgrade guard refuses detectable new extension/closure history. Live downgrade
still needs an explicit export/preservation plan.

The Phase 3 live privacy smoke searched for the substring `origin`, which also
matched the intentional new public `original_ends_at`. It now checks exact JSON
keys (and the automatic-origin value), preserving private-field checks. The real
request privacy suite remained green and the corrected two-process smoke passed.

Final review also moved the long repeated-window test out of transactional fixtures
into its own committed-data group. Independent sessions now observe both actual
commits across the real 32-second interval. Final native and container suites each
passed 273 examples after this test refinement.

## Phase 5 — Durable command outcomes (2026-09-25)

A lost HTTP response is a separate problem from transactional bid correctness.
The new wrapper claims a PostgreSQL unique key before touching Auction, executes
existing domain savepoints, then commits the public response with all mutations.
A snapshot CHECK failure proved that releasing an inner savepoint does not commit
its bid, private maximum, priority, leader or extension independently. A duplicate
waiting on the INSERT can take ownership after the original outer rollback.

JSONB normalizes object order, so both the first response and replay are rendered
from the persisted snapshot. Tests compare raw response bodies as well as IDs and
sequences. Replays return while another session holds the Auction row locked;
this is a stronger ordering check than observing the same final price.

Brakeman flagged the initial interpolated retention interval despite integer
validation. Using sanitize_sql_array for that expression removed the warning
without an ignore or weaker scanner configuration.

Bypassing the wrapper made both conflicting payloads succeed and made maximum
commands execute ten times. Checking the auction before replay returned 422 for
saved successes after closure. Both mutations were loaded from /tmp only. The
first sabotage run also revealed that RSpec's worker assertion exception bypassed
the shared cleanup rescue, leaving two committed fixtures. Final CI exposed those
rows through collection/seed assertions. Cleanup now handles that specific RSpec
exception as well as StandardError; only the identified test fixtures were removed.
Repeating sabotage verifies that all five domain/idempotency tables are empty
before running the normal verification suites. Development demonstration data is
retained separately.

## Phase 6 — Unknown outcomes reach the browser (2026-09-26)

The UI needs to preserve identity across a lost response, not merely disable a
button. A shared ref closes the same-render double-click gap; sessionStorage saves
one immutable command before fetch. A global recovery banner preserves it across
routes, actor selection is locked, and a tab reload restores it. The real browser
experiment forwarded a bid to Rails, observed 201, then dropped that response.
Reload plus explicit retry recovered the original result under the same key/body
without another history row. Current state still came from a fresh GET.

The same-origin rewrite exposed two development configuration boundaries. Rails
rejected the Compose `api` host until it was specifically allowed in development.
Next.js 16.3.6 rejected dev resource/HMR access from 127.0.0.1; initial SSR skeletons
therefore appeared but hydration did not finish. Reading the installed Next docs
and adding explicit loopback allowedDevOrigins fixed the real browser failure.
Framework development HMR is not auction realtime delivery or Phase 7 work.

The presentation header initially used only after_action. A request spec proved
that Rails skips that callback on rescued errors. The shared expected-error renderer
now calls the same timestamp helper; ordinary responses retain the callback. The
header is fresh application time only, never bidding authority or a replay snapshot.

Playwright's Chromium CDN returned a region-access HTTP 403. Rather than disabling
browser verification, the suite ran against the installed Google Chrome executable.
A first responsive assertion also matched Next's route-announcer alert in addition
to the form error; the test now targets the amount's associated error element.
The assertions still verify visible error copy and focus. Final screenshots inspect
real 390/768/1440 layouts, long titles, large prices and populated history. These
are functional/layout checks, not cross-browser or accessibility certification.

An explicit refresh failure could previously retry with the next pagination cursor
instead of the failed first-page request. The list now retains the failed cursor;
a regression test proves refresh retry replaces the first page without duplicate
cards. Another read test resolves an older GET after a newer one and confirms the
newer state remains visible. This is local request ordering, not a promise that
independent Rails GETs share one database snapshot.

## 2026-09-29 — Phase 7 public invalidations

Chose PostgreSQL Action Cable for real multi-process fanout without introducing
Phase 8 Redis. Public revisions belong to the existing logical locked mutation,
not each generated Bid. Rails transaction-owned callbacks preserve outermost-commit
semantics through savepoints; transport failure is downstream of acceptance.

Verified separate A/3001 writes and B/3002 sockets, two browsers, private-only
silence, proxy settlement, extension, closer publication and reconnect REST recovery.
The async-adapter sabotage confirmed why same-process tests are insufficient.
Publishing immediately made three rollback/visibility specs fail; removing the
stale-hint guard failed the coalescing test. All mutations were restored.

Test development exposed two harness errors: rejected channel subscriptions cannot
use RSpec's subscribed-only stream matcher, and WebSocket capture must distinguish
Next development traffic and Cable heartbeat frames from application notifications.
The final captures filter `/cable` and `auction.changed.v1`; actual notification
fields remain checked exactly. Initial failed runs are not counted as successes.

The migration was exercised down/up inside a rolled-back test-only transaction:
all existing row fields were preserved, zero was backfilled, and a nonzero revision
blocked downgrade. No development data reset was used. A small committed maximum
replay test also verifies that replay produces neither revision nor publication.

Applying the final Compose worker setting interrupted an extra container RSpec run
(exit 137), leaving a committed concurrency fixture before its cleanup hook could
run. The next run exposed that fixture in collection/seed/closer tests. We inspected
the failures and reset only the explicitly checked hammerfall_test domain tables,
then reran the container suite. Development data was untouched.

## 2026-09-30 — Phase 8 job boundary

Keeping PostgreSQL Action Cable while adding Sidekiq avoided an unnecessary
adapter change. The after-commit callback now enqueues only public identifiers;
the job checks current revision before broadcasting. A worker-stop run made the
notification queue grow 0 → 3 while bidding committed, then drain after restart.
With Redis stopped, HTTP acceptance and exact idempotent replay still succeeded,
but the enqueue warning proved that the hint was lost. Restarting API with Redis
still down also succeeded. This makes the commit/enqueue gap observable; it is not
solved by the Redis AOF volume or a retrying worker.

Sidekiq 8.1.7's CLI did not accept `-r ./config/environment` without the `.rb`
suffix in this runtime: the container repeatedly printed usage and restarted.
Using `-r ./config/environment.rb` booted Rails and processed queued jobs. Compose
`--wait` can report a service running during a restart loop, so we checked worker
logs and actual queue processing rather than treating startup alone as proof.

The read-only sweep uses a lateral latest-Bid lookup in one PostgreSQL statement
per bounded batch, avoiding a cross-query false drift during concurrent commits.
A 101-auction spec exercised cursor chaining beyond the first 100 rows. A test
expectation initially used `not_to receive(:error)` across both a clean and an
intentionally corrupted scan; the RSpec expectation remained active during the
second half. Capturing messages in an array made both assertions independent.

Three test-process-only mutations confirmed the checks fail for early publication,
stale requested revision broadcast and uncaught enqueue errors. No source mutation
was retained. The full normal container suite later passed 359 examples.

## 2026-09-30 — Phase 9 closes the API commit/enqueue gap

A real Rails process committed an auction bid, revision and three pending outbox
rows, then killed itself. Another process saw those rows and published them.
Stopping Redis during a later bid left PostgreSQL healthy and the outbox pending;
retry state survived until Redis returned. This directly distinguishes durable
publication intent from an after-commit callback held only by the API process.

Killing the publisher after Redis accepted a job but before PostgreSQL
acknowledgment produced two successful worker executions on retry. The row lock
rolled back and kept the event discoverable. The job's current-revision read and
public-only hint kept duplicate delivery harmless. `SKIP LOCKED` let another
publisher advance a different row while the first row stayed locked, without a
global lock or same-auction ordering guarantee.

The outbox acknowledgment is the queue boundary, not Cable receipt. Redis loss
or a dead job afterward still needs REST recovery and operational attention.
The publisher therefore logs pending age/retry counts, preserves poison rows,
and uses a finite Redis network timeout to avoid holding its row lock on a
stalled network operation. No overall wall-clock delivery bound was inferred.

Final review found a clock mismatch: PostgreSQL selected due rows, but the
publisher host initially calculated the next retry and pending age. A host set
far ahead could defer an event far longer than the configured backoff. Retry,
acknowledgment and age now read PostgreSQL `clock_timestamp()`; a one-year host
skew spec and a final live Redis outage/recovery passed. Assigning `Arel.sql`
directly to typed ActiveRecord datetime attributes initially typecast the
expression and made rows immediately due; focused tests caught this, so the
final code reads a timestamp value explicitly.

The old independent Cable verifier assumed exactly one hint. When earlier
lifecycle outbox rows were delivered after a bid, their jobs read the current
revision and legitimately sent duplicate current hints. The verifier now checks
that the bid revision arrives and every observed hint stays on the correct
auction stream and within the current revision range.

## 2026-09-30 — Phase 10 keeps Kafka below the commit boundary

Adding Kafka to the existing committed outbox row preserved the Phase 9
Sidekiq/Cable path. A real broker stop let a new bid commit at revision 4 and
the Sidekiq hint enqueue while Kafka attempts persisted an error and backlog.
After restart, the publisher drained the row and the audit group caught up.
The consumer's group rebalanced after broker restart; broker acknowledgment
preceded its audit entry, which is why these must be observed separately.

Killing a publisher after its delivery report but before PostgreSQL
acknowledgment yielded two Kafka records with the same event ID, one receipt
and one audit entry. Killing the consumer after the database effect but before
offset storage replayed the record as a duplicate on restart. A version 2
poison record stopped the group at its offset while a later bid and both
publishers still advanced. An explicit reviewed offset reset let the later
event through; replay from the beginning suppressed all previous effects and
stopped at the same poison. These are concrete at-least-once boundaries.

The first Compose consumer retained an old restart policy after its YAML was
edited during startup, producing a brief poison restart loop. Stopping and
recreating it applied `restart: no`; the runbook now relies on a stopped
consumer for deliberate poison review. A focused privacy assertion also
matched the substring `origin` inside `original_ends_at`; checking exact
field names preserved the actual privacy invariant without false positives.

## 2026-09-30 — Phase 11 treats Redis as a replaceable observation

The local Kafka topic retained a Phase 10 poison record. A new earliest-offset
projection group stopped on it, as designed. For the controlled live campaign,
the group's local offsets were reset to the topic tail and PostgreSQL seeded
current state. This made the operational rule concrete: a group offset and
finite Kafka history cannot be treated as a backup of current auctions.

Deleting the projection namespace and fully flushing an isolated Redis DB
both left PostgreSQL state intact. A manual seed restored current public
revisions; older Kafka replay could not lower them. An abrupt consumer exit
after Redis write but before offset commit replayed a duplicate on restart.
One malformed key made the read fall back but blocked replay/seed until that
single key was removed. The runbook documents this manual repair boundary.

Four temporary sabotages made stale ordering, equal-revision conflict,
PostgreSQL fallback and rebuild privacy checks fail as expected, then were
restored. Finalization found that the new real-Redis integration spec needs a
Redis service in the API CI job; the workflow was updated accordingly. This
phase exposes staleness rather than hiding it and leaves scheduled drift
repair for a separately requested Phase 12.

## 2026-10-01 — Phase 12 bounds repair and its own scheduling load

The checker can seed a missing or lower-revision Redis key from current
PostgreSQL state, but must preserve equal-revision conflicts, invalid keys and
ahead revisions for review. A real Kafka message arriving between comparison
and seed proved the existing atomic writer prevents an old repair from
regressing the key. Redis outage left a PostgreSQL bid accepted; PostgreSQL
outage stopped comparison rather than promoting Redis. Four temporary
sabotages made the corresponding safety tests fail.

The live campaign then exposed a different risk: 100-row jobs were bounded,
but every scheduler tick could begin another full chain. A PostgreSQL lease
per scan type now limits scheduled overlap. The first lease design used an
owner token and expiry, but review found that Sidekiq replay after a successor
enqueue could fork a chain with the *same* token. Cursor compare-and-advance
fences that handoff. A crash after advancement but before enqueue cannot be
made exactly once by this queue; expiry and restart from ID zero preserve
eventual progress. The lease coordinates maintenance load only and never
touches auction command decisions.

## 2026-10-01 — Phase 12.5 review: semantic state and stale lease expiry

The Kafka codec checked the shape of each public field, but a complete,
well-typed snapshot could still contradict PostgreSQL's price, deadline and
closure constraints. Redis read validation previously manufactured a Kafka
envelope to reuse that shape check. A small public-only validator now gives
both paths one semantic contract, and a deliberately impossible Redis value
with a recomputed digest is still escalated for review.

The reconciliation lease had token/cursor fencing, but a claimant waiting on
the row could reuse the `EXCLUDED` expiry calculated before the wait. A short
lease and a real PostgreSQL lock-wait test exposed the timing; the conflict
update now samples database wall time after the lock. Fencing still handles a
worker whose single row takes longer than the lease; it may duplicate bounded
maintenance work, not decide an auction outcome. Publisher I/O and idempotency
key privacy remain for the next Phase 12.5 session.

## 2026-10-01 — Phase 12.5 publisher tradeoff and retry privacy

Both outbox publishers select from the same table with `FOR UPDATE SKIP LOCKED`.
A controlled delay showed a Kafka publisher holding an idle PostgreSQL
transaction while Sidekiq skipped its row; the reverse direction also held.
This does not serialize different rows or touch the auction lock, but every
publisher process occupies a database connection throughout external I/O.
Live broker failure persisted retry state and broker recovery acknowledged the
same immutable event. A database CHECK rejection after Sidekiq acceptance
rolled back the acknowledgment and caused a safe duplicate on retry. The review
retained the simpler transaction protocol pending measured capacity evidence;
claims would require expiry and stale-owner fencing.

Unkeyed SHA-256 hides raw idempotency keys in ordinary database browsing but
does not protect weak keys from offline guessing after a table leak. A safe HMAC
rollout must account for existing unversioned rows and synchronized secret
rotation across instances. That migration was deferred to the security phase
without changing replay behavior during this repair pass.

## 2026-10-01 — Final review found a missing deadline relation

The public validator checked `starts_at < ends_at` and
`original_ends_at <= ends_at` but these do not imply the original deadline is
after the start. Ordinary create/edit commands already set a valid original
deadline, yet a malformed stored row or derived snapshot could state an
impossible original term. Phase 12.5 finalization added the missing
`starts_at < original_ends_at` condition to the shared public validator,
Auction validation and PostgreSQL CHECK, with Kafka, Redis, model and SQL
regressions. Local development/test databases had no violating rows before
the migration.

## 2026-10-01 — Hosted CI exposed setup drift

Local gates did not predict GitHub's service-container creation failure: two
hosted API jobs stopped before checkout with Docker exit 125. Starting the same
PostgreSQL and Redis images through the repository's Compose path let hosted
RSpec run. Brakeman's generated `bin/brakeman` injects `--ensure-latest`; a new
8.1.0 release made the pinned 8.0.6 exit 5 although its earlier local scan
was clean. Updating the lockfile restored the security gate. The Compose job's
host `npm ci` exited 243 when run after stack startup, but passed when moved
before the build; the public annotation did not expose npm stderr, so the
precise environment cause remains unknown. Installed runner Chrome then ran
the real browser suite. The final API, web and Compose jobs all passed on
`1135838`, demonstrating why hosted execution belongs in phase completion
evidence even after equivalent local checks pass.

## 2026-10-01 — OpenTelemetry Ruby exporter and metric-view traps

An explicit OTLP exporter `endpoint:` is treated as the full URL by the Ruby
exporters. Supplying only the Collector origin sent data to `/`, while manual
HTTP connectivity looked healthy. Appending `/v1/traces` and `/v1/metrics`
made real spans and counters arrive. The Ruby metrics SDK also treats a
matching view without a concrete aggregation as non-recording; counter views
with only an attribute allowlist silently dropped counter data. Hammerfall now
normalizes dimensions at its instrumentation boundary, applies explicit
histogram views for boundaries, and leaves counters on their default monotonic
sum. Inspecting actual Prometheus series and Tempo traces exposed both issues;
successful application tests alone did not.

## 2026-10-01 — Async telemetry needed real transport and privacy checks

`rdkafka` 0.30 accepts producer `headers:` and exposes consumed `message.headers`;
the public Kafka envelope needed no version change. A live Tempo trace joined
HTTP outbox persistence, Sidekiq enqueue/worker/broadcast, Kafka publish, audit
and projection consumers through transport context. Event UUID remained separate
from trace identity. Collector/Tempo/Prometheus/Grafana outages left proxy bids
working and outboxes drained; the Collector outage emitted exporter errors.

Actual Collector output exposed `_ratio` names for count gauges created with
unit `1`, so those gauges now omit a unit. Actual development logs exposed SQL
with inlined private maximum and priority values even though Rails filtered
request parameters; info-level development logging removed the SQL debug lines.
Filtering whole command payload keys also removed titles and descriptions from
Rails info request logs.
Concurrently running live development and test processes shared Redis DB 0,
causing projection spec collisions when numeric auction IDs overlapped. Redis
DB 1 isolated the focused test run. Publisher backlogs are global PostgreSQL
counts, so Grafana uses `max` across replicas instead of summing them.

## 2026-10-01 — Final observability checks need clean test transport context

The gated Kafka examples use `KAFKA_BOOTSTRAP_SERVERS=kafka:9092` when run
inside the API container; the native default `127.0.0.1:29092` points at the
container itself. Interrupting the initial unreachable-broker run left a test
outbox row. The publisher test correctly selected that older due row, so I
reset only `hammerfall_test` before the clean three-example live rerun.
This was a test-environment artifact, not a production publisher defect.

A fresh 19-span trace showed one short HTTP root with later Sidekiq and Kafka
work under propagated context. Prometheus `series` included historical `_ratio`
names from processes before the gauge-unit fix, while an instant query showed
only the corrected current gauges. Instant samples and process identity matter
when judging a final metric contract. Controlled loss and repair of one derived
Redis key produced cumulative repair counters without changing PostgreSQL.

## 2026-10-01 — Phase 14 benchmark setup failures were measurable

The first normal smoke's `iteration % 10` workload slot and `iteration % 8`
auction choice correlated: some auctions never received maximum commands.
Decoupling auction choice from the slot spread manual and maximum commands
across all eight. The first 30-second run found API `OTEL_ENABLED=false`
despite running Collector/Prometheus containers; container health alone did
not prove application instrumentation. An early hot after-snapshot captured
fewer lock histogram samples than k6 bid attempts. Waiting 20 seconds for
export/scrape settlement yielded exact agreement (1,519/1,519 in the primary
hot run). These exploratory results remain labeled and should not be mixed
with the committed-harness primary comparisons.

At 8 VUs on one auction, the primary run showed a ≤50 ms p95 lock-wait bucket
and 96.42 ms p95 bid HTTP duration, with 370 accepted and 1,149 expected
rejections. One during-run sample saw 4 Sidekiq and 7 Kafka pending outbox
rows, all drained afterward. This is evidence for deeper Phase 14 isolation,
not proof of a saturation point or grounds for a Phase 15 redesign.

## 2026-10-01 — Phase 14 load separated HTTP queueing from auction lock wait

The hot closed-loop steps flattened near 84–101 HTTP/s while p95 rose to
935 ms at 64 VUs. Lock-wait p95 remained in a ≤25 ms bucket at that step and
bid processing p95 was ≤100 ms; k6 consumed about 14% CPU and API about one
core. Thus the initially plausible row-lock-tail hypothesis was not supported
by this local evidence. One PostgreSQL sample did catch a transaction-ID lock
waiter at 32 VUs, so row serialization exists; its measured duration did not
explain the HTTP tail. The 3-connection Rails pool had no checkout-wait metric,
and Puma admission wait was also unmeasured. Phase 15 needs profiling at those
boundaries before any concurrency or pool change.

The 1,000 final-ten-second challenge was a useful failure, not a performance
score: all VUs launched, but the API's 1,024 open-file soft limit produced
28 `Errno::EMFILE` responses and 64 k6 timeouts. PostgreSQL held 911 completed
command records against 908 acknowledged successful/expected responses, at
least three ambiguous HTTP observations with DB outcomes. State remained
correct after extension and closer. A 600-bidder burst was clean with p95
8.81 seconds; it is the highest clean local attempt, not production capacity.
At 500 Action Cable clients, all confirmed subscriptions received server
invalidations, while handshake p95 reached about 2 seconds. These are k6
receipts, not a claim of universal browser delivery. The [Session 2 report](benchmarks/phase-14-session-2.md)
preserves unfavorable runs, sampling limits, recovery checks and Phase 15
investigation classes. No auction or runtime optimization was made.

## 2026-10-01 — Live projection consumers can invalidate native test assumptions

The full Phase 14 regression initially failed 11 reconciliation examples,
even though the auction benchmark checkers had passed. Native RSpec and the
running Compose projection consumer both used Redis DB 0, while test and
development PostgreSQL sequences could produce the same auction IDs. The
consumer created or advanced a key just as a test expected it missing. A
focused rerun against Redis DB 15 passed, and the full gate passed after
`scripts/check` assigned that isolated test endpoint. This was a test
environment collision, not evidence of an auction-state failure. The useful
lesson is to isolate derived-state namespaces as well as SQL databases when
running live integration stacks beside native tests.

## 2026-10-01 — Puma admission was the missing local hot-tail boundary

At 64 hot VUs the Puma 8.0.2 backlog sampled around 58 while its three
request threads were saturated. Direct Active Record queue instrumentation
saw no blocking wait; all 5,133 checkout samples were ≤1 ms. The lock p95
bucket was ≤10 ms, far below HTTP p95 ~782 ms. Puma did not supply a
per-request acceptance-to-Rack timestamp, so backlog plus service rate is a
causal indication, not an exact admission percentile. A StackProf capture
showed Rails development file checks at 13.3% inclusive CPU samples; avoid
mistaking that local file-watcher cost for an auction rule bottleneck. The
[profiling report](benchmarks/phase-15-session-1.md) preserves all commands,
measurements and caveats. No tuning was adopted at this milestone.

The 200-subscriber fanout used 202 HTTP sockets at peak and the API returned
from 20 to 23 descriptors afterward. This supports ordinary connection
pressure behind the 1,024-FD failure and gives no short-run leak signal.
The Phase 14 1,000-contender errors remain real; raising the FD limit is a
separate diagnostic experiment, not a correctness fix or capacity claim.

## 2026-10-01 — More request threads can move a queue into the DB

After measuring development reloading and diagnostic overhead, five Puma
request threads with a fixed three-connection pool produced roughly 2,300
blocking pool waits per 20-second hot run. Raising the pool to five removed
those waits but increased PostgreSQL sessions and auction-lock waiting in
the valid sample, without improving accepted useful work. The correct
decision was to retain three threads/pool three. A later restored baseline
ran much slower than an earlier identical configuration, so even repeated
local runs need a bracketed control and explicit host-drift limits. The
[Session 2 report](benchmarks/phase-15-session-2.md) retains the full matrix.

Development request reloading accounted for a measurable local service-rate
cost, but removing it did not reliably lower p95/p99 or backlog. API OTel
off increased throughput in repeated runs; keeping it on preserves the
lock/pool/outbox/error visibility needed to operate this system. These are
distinct decisions: a measurable overhead does not by itself justify a
production visibility loss.

## 2026-10-02 — Final gates found a diagnostics eager-load mismatch

The new DB pool diagnostic file defined two sibling modules but no constant
matching its Zeitwerk path. Request tests could pass because the initializer
required the file directly; `zeitwerk:check` still failed on eager load. Moving
the modules under `Observability::DbPoolDiagnostics` and updating the prepend
targets repaired the contract. Focused and full gates passed afterward. This
is a reminder to run eager-load checks on opt-in instrumentation even when
default runtime smoke looks healthy. The [final gate index](benchmarks/phase-15-final-gates/README.md)
records the failure and recheck.

## 2026-10-02 — Short chaos faults can outrun scraped metrics

Phase 16's Redis, broker and publisher outages produced fixture-specific
PostgreSQL outbox backlogs that bounded Prometheus snapshots sometimes missed
because the global gauge's last scrape still reported zero. Direct outbox
queries, consumer duplicate logs and public endpoint comparisons gave the
decisive evidence. The same session proved that deleting a derived Redis key
can be repaired by the existing reconciler, while shared Sidekiq Redis data
should not be flushed just to simulate projection loss. See the
[Session 1 chaos report](chaos/session-1.md).

## 2026-10-02 — Crash evidence needs both sides of the boundary

The publisher's broker receipt alone was insufficient until PostgreSQL still
showed a pending row after process death and a restarted publisher caused
both Kafka groups to log the same event ID as duplicate. For the audit
consumer, receipt/effect counts and Kafka committed offsets supplied the
complementary proof. A self-sent `SIGKILL` from a Puma request logged the
intended command boundary but still let a 201 response complete; synchronous
`Process.exit!` produced the actual lost connection. These invalid harness
runs were retained, not promoted to correctness evidence. See the
[Session 2 report](chaos/session-2.md).

## 2026-10-02 — A connected socket can still miss a notification

The browser stayed connected to the API/Cable process while Sidekiq and its
outbox publisher were stopped. PostgreSQL accepted a bid and REST showed the
new price, but the observer's history remained empty without a hint. An
explicit REST refresh recovered it; after the workers restarted, a later
revision hint prompted another REST read. This separates socket liveness from
notification completeness. Phase 16 also found that event crash hooks lacked
the command hook's atomic one-shot marker; adding the marker made respawn
safety explicit without changing ordinary event delivery. See the
[final review](chaos/phase-16-final.md).

## 2026-10-02 — Cross-process realtime and lock-chain evidence

A browser socket on replica `a` received a revision hint from a bid handled by
`b`, and the inverse also worked through PostgreSQL Cable pub/sub. The browser
rendered the REST-fetched price. Stopping the socket owner closed the socket;
automatic resubscription occurred in one run but not within 30 seconds in
later runs. A visibility REST read recovered each committed bid, and the
rejoined replica read current SQL state. This variability needs final-session
investigation, even though no auction truth was lost.

The deadline harness initially misread its own lock evidence. Rails cached a
repeated `pg_stat_activity` count; then a direct-blocker-only query omitted a
second waiter queued behind the first. Clearing the statistics snapshot and
counting the transitive chain produced two observed waiters. Releasing after
PostgreSQL time crossed the deadline yielded two valid rejections, while a
separate near-deadline run serialized two accepted bids and one extension. See
the [Session 2 report](multi-instance/session-2.md).

## 2026-10-02 — A reconnect attempt can be hidden behind an upstream timeout

The first CDP view showed only that a stopped Cable owner's socket closed and
no new handshake appeared in 30 seconds. Recording socket creation and
handshake attempts showed the browser had already retried. Nginx was waiting
on the dead container because `/cable` lacked the ordinary HTTP route's
five-second upstream connect timeout. Adding it allowed retry to the live
replica. The upgrade diagnostic header then contained both upstream addresses;
the harness initially called the successful `b,a` route `b`. Parsing its last
address and excluding Next HMR sockets made the evidence accurate. No second
client reconnect system was needed. The [final review](multi-instance/phase-17-final.md)
records the local repeat and remaining interruption limit.

## 2026-10-02 — Kubernetes readiness and local broker naming

The first kind API pods failed readiness with connection refused during boot,
then became Service endpoints only after Rails answered a PostgreSQL query.
Deletion removed one endpoint and added a replacement without moving auction
state; a third API handled requests after manual scale. This is the useful
orchestration boundary: Service membership and pod identity alter execution
placement, while PostgreSQL retains ordering and outcome. Kafka's advertised
`kafka:9092` needed a matching Kubernetes Service name even though the broker
remained in Compose; the generated EndpointSlice routes it to the external
container. The [Session 1 report](kubernetes/session-1.md) retains evidence.

The cached multi-platform Nginx image could not be imported by `kind load`
because an archive digest was absent; letting the node pull Nginx worked.
Recursively changing ownership of the full web dependency tree also made the
first image build unreasonably slow; ownership of copied source and `.next`
was sufficient for the subsequent build. Neither issue changed auction logic.
The first Secret generator piped `printenv`, which appended a newline to the
password bytes. A byte comparison caught the mismatch even though local
database queries succeeded. Printing with `printf %s` inside the Compose
container preserved the actual environment value without exposing it in logs.

## 2026-10-02 — Fresh kind recreation and endpoint drain

The final fresh-cluster run exposed kind v0.33's default Kubernetes 1.37
server as two minor versions beyond the installed kubectl 1.35. The setup now
pins the release's Kubernetes 1.36.4 image by digest; a zero-object rebuild
then used a supported client/server pair. Image builds, generated Secret and
endpoints, one-shot database preparation, and all application roles completed
without manual resource patches.

Deleting an API pod during 40 reads produced one HTTP 502. Nginx logged an
upstream connection refusal while its API Service target changed; the next
reads succeeded and a new pod read the same revision. This is a useful limit
to the phrase “two healthy replicas”: readiness and endpoint withdrawal
reduce disruption but cannot guarantee that every in-flight or immediately
adjacent request succeeds. Safe GET retry and keyed command replay still
belong to clients, while PostgreSQL preserves the result. The
[final report](kubernetes/phase-18-final.md) records the exact proof boundary.

## 2026-10-03 — Phase 19 managed-service contract check

The first dummy production Rails boot with only a master-key assumption failed:
this repository has no encrypted credentials file, and Rails required
`SECRET_KEY_BASE`. A file-backed key path then booted locally. This is why
mounting a secret is not equivalent to proving an application can consume it.
The Kafka review found Google's documented non-Java loopback OAuth helper for
librdkafka, so the GKE overlay includes a real sidecar contract instead of
assuming Java credentials work in Ruby. A final static pass also caught a
Google service-account name length edge case, duplicate Cloud SQL TLS query
keys, and Kafka API enablement outside the broker gate; all were corrected.
[Session 2](cloud/session-2.md) holds the evidence and remaining live gaps.

## 2026-10-03 — Cloud overlay isolation and least privilege

The final base regression caught `k8s/local/up.sh` applying the new
`kustomization.yaml` as if it were a Kubernetes object. Rendering the base
worked, but the original direct-file apply path did not. Skipping that build
instruction restored the fresh local kind rollout. Static cloud mount review
also found the PostgreSQL-only auction closer sharing a Redis-capable KSA and
CSI class with Sidekiq workers; a separate closer KSA and database-only mount
now match its actual dependency. These are examples of why an overlay needs
both static isolation checks and a real base deployment regression.
# Phase 20 Session 1 discovery — actor continuity under session expiry

The existing idempotency table's actor ID and canonical fingerprint did not
need a schema migration when HTTP identity changed. Authenticating first and
passing the verified user ID preserves retained outcomes; an expired cookie
returns 401 before key claim, and a new session for the same user can replay
the unchanged command. This avoids turning authentication expiry into an
irrecoverable ambiguous bid. The trade-off is a PostgreSQL lookup per request
and a remaining post-handshake Cable expiry window. See ADR-016 and
`spec/requests/identity_security_spec.rb`.

## 2026-10-03 — Session 2 transport and key migration

The first real Next/browser pass exposed different generated Rails secrets on
the two development API replicas. Login succeeded, then cross-replica session
resolution failed. Sharing the local `api_tmp` volume made the same encrypted
cookie usable on both; the direct A/B script then proved revocation and bid
replay across replicas. This was a transport configuration defect, not a reason
to add sticky sessions.

The idempotency migration needed a lock on the logical raw-key scope before
checking HMAC and legacy SHA representations. Otherwise two versions could
both miss and claim different digest rows. The lock is transaction-scoped in
PostgreSQL, and old executors must be drained before deployment. During the
backend gate, the first run used the default three-connection pool against a
ten-worker concurrency spec and timed out at checkout; rerunning with pool 15
passed the focused concurrency spec and the full suite. The frontend recovery
test also raced session loading; waiting for the signed-in state removed the
flaky click without changing retry behavior. The [Session 2 report](security/phase-20-session-2.md)
records the control behavior and proof limits.

## 2026-10-04 — Phase 20 final integration

Migrating the old smoke clients exposed the practical effect of the new
security boundary: every mutating request needs an authenticated actor and
CSRF, while a retry must retain its original key and payload. Reusable local
clients made that explicit. The browser suite initially lost Cable admission
because it browsed `127.0.0.1` while Compose hardcoded a `localhost` socket.
A handshake capture showed no Cookie header on that socket even though session
GET succeeded. Deriving the local Cable URL from the browser host repaired the
same-origin identity path; the full browser and worker-outage scenarios passed.

The final application proof used a regenerated shared development Rails secret,
real A/B replicas, PostgreSQL, Redis and Kafka. When a limiter window delayed a
fixture, a 70-second closer test entered the soft-close window before its first
bid. Giving that test a longer real deadline preserved the intended closer
behavior without bypassing authentication or time authority. A ten-worker
idempotency script similarly keeps each race intact while allowing Redis
admission windows to reset between independent scenarios. The final report
records the exact local evidence and cloud/operational limits.

The first hosted closure run exposed the API job's default five-connection
test pool: four ten-worker idempotency examples timed out. Reproducing the same
focused failure locally and rerunning with a 15-connection pool isolated the
runner configuration error. CI now sets `RAILS_MAX_THREADS=15` explicitly;
the concurrency tests retain their original worker count.

## 2026-10-04 — Phase 21 policy research and stepped increments

The current Catawiki help table chooses increments from the visible price and
explicitly warns that experiments can change individual lots. That made a
single global replacement of Hammerfall's fixed increment inappropriate:
historical auctions need their existing policy, while a new opt-in policy can
model the published schedule. The proxy resolver must look up the increment at
the losing bidder's newly visible ceiling, which can cross a price band.
The first focused test run caught mistaken test expectations at €105 and €200.01;
the current-price band, not the bid's earlier band, yields the correct increment.
The independent-connection race also showed that both lock orders can yield
one acceptance: after either €105 or €110 is accepted, the next minimum jumps
past the other bid. The test now asserts both valid serial outcomes and the
fresh rejection details. See [ADR-018](adr/018-stepped-bid-increments.md).

## 2026-10-04 — Hidden reserve changes the meaning of winner

Reserve could not be implemented as a nullable column alone. The old model,
SQL check, PostgreSQL consistency sweep and strict public snapshot validator
all treated a closed leader as sale winner. The reserve slice now separates
competition state (`current_leader_id`) from sale outcome (`winner_id`), and
keeps the distinction through Kafka, Redis, reconciliation and the browser.
The v1 Kafka snapshot was intentionally closed to new fields, so reserve
status required v2; retained v1 events normalize as historical unreserved
state when replayed to the v2 projection. A test migration rollback/reapply
also confirmed the downgrade guard rather than promising to discard a
configured reserve. See [ADR-019](adr/019-hidden-reserve-policy.md) and the
[Session 2 report](marketplace/phase-21-session-2.md).

## 2026-10-05 — Rapid policy and historical projection compatibility

The rapid policy needed no second command or closer path: persisted mode feeds
one deadline calculation after locked proxy settlement. Independent connection
tests forced both bid/closer lock orders and replay after a lost response.
The less obvious upgrade issue was the existing Redis v2 digest. A historical
v2 entry has no closing field, while an equivalent replay now includes the
regular default. Treating those digests as an ordinary conflict would stop the
projection consumer. The reader validates the original digest before returning
normalized state, and Lua permits only an equivalent regular equal-revision
upgrade. A rapid replacement still conflicts. This preserves retained events,
public field allowlists and PostgreSQL authority without introducing v3.

Full browser verification also exposed a fixture that could expire during a
legitimate 60-second lifecycle quota retry. Timed fixtures now leave admission
headroom, then wait into the real policy window; the production limiter and
deadline checks remain exercised.

## 2026-10-05 — PITR exposes future transport state

The physical restore itself was straightforward: `pg_basebackup`, archived
WAL, selected LSN and verification reproduced T2 but excluded T3. The less
obvious failure was outside PostgreSQL. Redis already held T3's valid revision
5 and refused to lower it to restored revision 4. That refusal is correct for
ordinary delayed messages but blocks automatic PITR reconciliation. More
seriously, the existing Kafka projection consumer would accept a retained T3
event and rebuild the future state after an operator cleared Redis. The
recovery order must therefore fence consumers, quarantine the old broker,
restore authority, then rebuild/replay only events belonging to that authority.

The same exercise made a release boundary concrete: an old app could use the
expanded schema for fixed auctions, but still misprice a stepped auction.
Schema compatibility and behavior compatibility are separate tests. A
post-migration failure can allow an old image only before new policy data or
v2 events exist; later failures need a compatible forward fix.

## 2026-10-05 — Replaying the restored timeline

The isolated Kafka drill turned the suspected PITR failure into a measured
one: the old broker and Redis reached revision 5, while restored PostgreSQL
ended at 4. Stopping the old broker, seeding Redis from PostgreSQL and
republishing the four retained outbox rows to a fresh broker yielded exact
revision 4 state. Three restored audit receipts recognized duplicate event
IDs; the fourth event created one new receipt. Older projection events were
stale and the equal current event was a duplicate. This is a timeline
isolation procedure, not an exactly-once property or a filter in the
consumer. Accidentally reconnecting the old broker remains unsafe.
