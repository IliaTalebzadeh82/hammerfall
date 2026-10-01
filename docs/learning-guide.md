# Learning guide

## Repository foundation

**Problem:** provide a reproducible starting point for two runtimes and a real
PostgreSQL database before introducing concurrent business behavior.

**Naive implementation:** generate two unrelated projects, use SQLite locally,
and defer dependency locking and executable checks.

**Why it fails:** local database behavior diverges from production PostgreSQL;
implicit runtime assumptions and stale dependencies make results hard to reproduce.

**Chosen implementation:** a small monorepo with independently locked Rails and
Next.js apps, Docker Compose for local dependencies, and the same lint/test commands
locally and in CI. The Rails application remains the future authority.

**Verified behavior:** both apps boot and their foundation checks execute
against the declared runtimes. See progress.md for actual results.

**Not guaranteed:** auction correctness, concurrency safety, authentication,
production readiness, or any distributed delivery semantics.

**Read first:** README.md, docker-compose.yml, docs/adr/001-modular-monolith.md,
then docs/code-map.md.

**Tests to study:** the health request spec and the frontend starting-page test
in the scaffold. They exercise the boundary that actually exists.

**Interview discussion:** why defer microservices, why test against PostgreSQL,
and why liveness differs from database readiness?

## Core auction domain — Phase 1 (historical guarantees)

**Problem:** define what a valid sequential auction operation means before asking
how simultaneous operations should be serialized.

**Naive implementation:** accept a floating price from JSON, update status through
generic mass assignment, insert bids independently of current price, and label the
highest bidder a winner immediately.

**Why it fails:** floating point and permissive integer casting can lose value;
arbitrary status writes bypass business preconditions; a failed second write can
leave bid history and displayed price inconsistent; an active leader can still be
outbid and is not the winner.

**Chosen implementation:**

- Integer EUR cents with a documented bound and before-type-cast validation prevent
  fractional/string inputs from silently becoming different amounts. SQL checks
  independently protect stored ranges.
- Explicit schedule/activate/close/cancel methods expose transition edges and time
  preconditions. Model validations reject ordinary bypasses; no callback performs
  hidden lifecycle writes.
- Auction stores current_price. place_bid! validates and writes Bid plus price in
  one transaction. `requires_new: true` creates a savepoint when nested, so an outer
  caller rescuing a failure cannot accidentally preserve just the bid. This was
  verified with a failing regression test before the fix.
- PostgreSQL constraints protect row shape and references even when Rails validation
  is bypassed. They do not encode the whole mutable workflow or cross-row bid rule.
- Active leader is derived from the highest accepted bid. Only explicit close assigns
  winner_id; no bids means no winner. Timestamps gate bids but do not change status.

**Guarantees:** correct sequential minimum checks, explicit lifecycle behavior,
positive exact amounts, atomic bid/price persistence, one nullable winner reference,
and stable ordinary bid-history pagination. See invariants.md for scope and evidence.

**Not guaranteed:** two callers cannot both read the same price and accept competing
bids; the last current-price write can overwrite the other. A savepoint does not
serialize that read/check/write sequence. App-clock closing is not distributed
closure. Supplied bidder IDs prove no identity; retries have no deduplication.

**Read first:** app/models/auction.rb, bid.rb, user.rb, and
app/validators/minor_units_validator.rb under apps/api, then the migration and API
controllers/presenters mapped in code-map.md. ADR-002 records the state choices.

**Tests that teach the behavior:**

- spec/models/auction_spec.rb: edge matrix, time boundaries, frozen terms, and
  leader/winner distinction.
- spec/models/bid_spec.rb: first/subsequent minimum, stale sequential object reload,
  rejected bid persistence, and failed-price-write rollback including nested calls.
- spec/integration/domain_constraints_spec.rb: real SQL that bypasses validation
  and is still rejected by PostgreSQL; savepoints isolate expected SQL failures.
- spec/requests/auctions_spec.rb and bids_spec.rb: public JSON and error contracts.
- scripts/smoke-api: actual HTTP lifecycle and bidding against running Docker services.

**Interview discussion:** explain integer cents versus numeric/float; why a database
constraint differs from workflow validation; why atomicity is not isolation; why
server-issued IDs are not concurrent commit order; and why leader differs from
winner. Be explicit about what Phase 2 still has to prove.

## Learning roadmap

Add the problem, naive approach, failure modes, chosen implementation, guarantees,
limitations, source files, demonstrative tests, and interview explanation for each
subsystem when it is built:

- WebSockets (Phase 7)
- Outbox (Phase 9, implemented below)
- Kafka and consumer idempotency (Phase 10, implemented below)
- Redis projections (Phase 11)
- Reconciliation (Phase 12)
- Observability (Phase 13)
- Load testing (Phase 14)
- Kubernetes (Phase 18)

Do not substitute hypothetical explanations for evidence from implemented code.

## Bid serialization — Phase 2

**Problem and naive failure:** Phase 1's transaction makes its two writes atomic,
not its decision exclusive. At price 10000/increment 500, A and B both reload 10000;
A accepts 11000 and commits; B, already validated, accepts 10500 and overwrites the
price. A plain reload can be stale again immediately. A Ruby mutex would only help
one process. See ADR-003 for alternatives and the concrete transaction boundary.

**Chosen implementation:** lock and refresh the auction row in PostgreSQL before
validation, allocate MAX(sequence)+1 while locked, insert the bid, update price,
and commit. Existing lifecycle actions use the same lock. Waiters revalidate price,
status and the time window. No retry loop or external work belongs in the lock.

**Guarantees:** accepted manual bids serialize per auction across database sessions;
sequences identify that order; failure rolls back bid/price/sequence together.
**Limits of row locking alone:** no FIFO/fairness, global ordering, clock
synchronization, retry identity or throughput guarantee. Phase 5 adds retry
identity at the protected HTTP command boundary. A hot auction is a serialized resource. Independent
auctions can proceed concurrently; a long outer transaction delays lock release.

**Read first:** Auction#place_bid!, the sequence migration, BidPresenter, ADR-003,
and spec/integration/concurrent_bidding_spec.rb. The concurrency suite uses real
committed rows, independent PostgreSQL sessions and database-observed lock waits.
Transactional fixtures remain enabled elsewhere. Tests check outcomes, stale loaded
objects, rollback, lifecycle changes and independence, rather than mocking locks.

**Interview discussion:** explain atomicity versus isolation, why validation must
follow lock acquisition, why uniqueness is insufficient, how rollback affects
ordering, and why pessimistic locking trades simple correctness for hot-row queues.

## Automatic bidding — Phase 3 (historical scope)

**Problem:** a private spending ceiling is not a public offer. Setting 500 should
not cost 500 when the auction can be led for 100. A challenger can trigger several
visible bids, all of which must settle before anyone reads committed new state.

**Naive failure:** save Bob's 200 bid, commit, then enqueue Alice's counter. A crash
leaves Bob as leader despite Alice's binding protection; another request sees an
incorrect intermediate state. Simply dumping model JSON also exposes Alice's
unused maximum. Choosing the highest equal row by ID makes ties accidental.

**Implementation:** one MaximumBid per user/auction, increases only, each commitment
with a durable priority_sequence. Auction locks/reloads first, writes protection
when needed, invokes Bidding::ProxyResolver, and commits all visible rows with the
final current_price/current_leader_id. No asynchronous resolution or mutation
callbacks. See ADR-004's table, written before the implementation.

**Step-by-step (starting 100, increment 10):**

1. Alice authorizes 300: store private priority 1; emit Alice 100, visible sequence 1.
2. Bob manually bids 200: emit Bob 200 (sequence 2), Alice 210 (sequence 3), then
   commit price 210/leader Alice. Her unused 300 ceiling is absent from public JSON.
3. In a fresh contest Bob instead authorizes 400: emit Alice 300, then Bob 310.
   Bob pays only enough to win. All three records/price/leader commit atomically.
4. If Bob authorizes 305 instead, his final offer is 305, not unauthorized 310.
5. If Bob authorizes 300, emit Bob 300 then Alice 300. Price does not decrease;
   Alice's earlier priority wins. Equal visible amounts now have legitimate meaning.
6. If Alice had 200 and raises to Bob's already established 300, she gets a new
   priority and loses that tie. Old low-ceiling seniority does not carry forward.
7. A leader raising protection from 300 to 500 emits nothing and does not self-bid.

**Why two contenders suffice:** every completed contest leaves previous losers
exhausted at/below visible price or behind an equal-ceiling priority winner. A new
command only changes its caller's offer/protection. Comparing that caller to the
current leader therefore accounts for all stored instructions without repeatedly
incrementing against every historical bidder. This assumption must be reviewed if
future policy permits reductions, retractions or reserve prices.

**Leader and price:** explicit leader state is selected by ceiling and priority,
not last-row luck. The final visible row represents that selected leader and its
amount equals current_price. Normal rows never decrease; ties may remain equal.
The public origin is hidden even though internal Bid.origin explains the algorithm.
Manual offers may exceed a user's old proxy cap as a new explicit authorization.

**Privacy:** hidden inputs complicate requests, errors, SQL/debug logs, inspection
and serialization. Tests capture actual JSON and logger output with a distinctive
unused ceiling. Rails filters maximum_amount/priority/origin; explicit presenters
and an amount-free acknowledgement keep those fields private. Visible bids can
reach ceilings by design, but never label them as ceilings. Without authentication,
this is representation privacy, not secure identity or protection from probing.

**Guarantees and limits:** the same PostgreSQL auction row serializes every contest;
private instruction, priority, generated rows and price/leader roll back together.
More database work holds that row longer. No throughput/fairness promise follows.
One request can emit multiple rows; lock duration and connection queue pressure
remain the hot-auction bottleneck. No extensions, closing clock redesign, idempotency,
notifications or other later systems are implemented.

**Read first:** app/models/auction.rb, maximum_bid.rb and
app/models/bidding/proxy_resolver.rb under apps/api. Then read models/maximum_bid_spec.rb
for the table/property stream, integration/concurrent_maximum_bidding_spec.rb for
real sessions and SQL rollback, and requests/maximum_bids_spec.rb for JSON/log privacy.

**Interview discussion:** explain ceiling versus price, why equal bids are valid,
why priority changes on a raise, why asynchronous counters violate atomicity, why
stored leader is distinct from winner, why dormant maxima need no rebidding loop,
and why request filtering alone would not prove SQL/model-inspection privacy.

## Deadline decisions and soft close — Phase 4

**Problem:** five API processes cannot safely define one auction deadline using
five local clocks. `Time.current < auction.ends_at` can produce contradictory
answers. A punctual scheduler does not fix an API that accepts an expired active
row, and a row lock does not fix a clock captured before waiting.

**Why transaction time fails:**

```text
20:59:59  transaction B starts; transaction_timestamp() is 20:59:59
          B tries SELECT FOR UPDATE and waits
21:00:00  auction deadline passes
21:00:02  holder commits; B obtains lock
          transaction_timestamp() still says 20:59:59  [wrong decision clock]
          clock_timestamp() now says 21:00:02         [reject]
```

AuctionClock asks PostgreSQL for actual wall time only after the locking reload
returns, with Rails query caching disabled. It captures one decision time for the
entire logical command. The locking query and clock query use the same connection
and transaction. Database wall time is a shared authority here; it is not immune
to host clock corrections and does not solve a hypothetical multi-region design.

**The boundary:** active status plus starts_at <= decision_time < ends_at permits
bidding. Exactly at the end is expired. HTTP arrival and transaction start are
irrelevant. Acceptance is a locked decision; physical commit can happen later.

**Bid wins the lock first:**

```text
Bid                                  Closer
lock auction                         discover old deadline
DB clock = 20:59:55                   try lock; wait
valid; resolve entire proxy contest
ends_at: 21:00:00 -> 21:01:30
save all state; commit               acquire lock + reload
                                     DB clock = 21:00:01
                                     see 21:01:30; not due; no-op
```

A genuinely due stale discovery can happen while that extension is **uncommitted**:
at 21:00:01 a READ COMMITTED candidate query still sees the old 21:00:00 end. That
is why the finalizer must reload after waiting. Candidate IDs are hints, not proof.

**Closer wins after expiry:**

```text
Closer                               Bid / maximum request
lock auction; DB clock = 21:00:02     try lock; wait
closed; winner = current leader
closed_at = 21:00:02; commit          acquire lock + reload
                                     see closed; reject; no new bid/max/extension
```

Every closer uses the same operation. If eight closers discover the same ID, the
first due transition chooses winner/closed_at; later callers return those exact
values. Leader election would add machinery without fixing anything the shared
row lock and fresh revalidation have not already handled.

**Scheduler punctuality is not deadline correctness.** If the closer is stopped,
status can remain active at 21:00:30, but a request still reads the DB clock under
lock and rejects auction_ended. This implementation does not commit lazy closure
through a rejected command. A restarted closer or explicit close finalizes later.
No-traffic auctions still close because polling is independent of requests.

**The four times:**

```text
starts_at          earliest eligible time; activation is still explicit
original_ends_at   scheduled finish frozen after draft
ends_at            effective legal deadline, including extensions
closed_at          DB time when finalization was decided; may lag ends_at
```

closed_at is not exact commit time and never means bids were legal until then.
Legacy closed_at is an explicitly documented backfill estimate. All public times
remain UTC; local display belongs to the future frontend.

**One external commitment is the extension unit.** With 37 seconds remaining,
adding 90 to the old end leaves 127 seconds, not 90. Bob's manual offer plus Alice's
automatic counter produce two Bid rows but one extension. Alice raising her own
max without any visible bid still makes a binding commitment and can extend once.
Repeating the same ceiling or submitting an invalid bid extends nothing. There is
no extension cap; a later accepted command in the new final minute extends again.

Auction keeps this arithmetic after synchronous resolution and before its final
UPDATE. Committing a bid before extending would let a closer finalize the old
deadline between those writes. A real SQL constraint rejection of the extension
proves rollback removes all generated bids, max changes, priority, price and leader.

**How the tests prove time rather than fake it:** pure AuctionDeadline examples use
exact rational offsets for 60.001, 60, 37, one microsecond, equality and after-end.
Integration fixtures use deadlines relative to actual DB time, without mocking
clocks or locks. Race tests observe pg_blocking_pids, explicitly start transactions
before expiry, then wait for the real DB clock before releasing the holder. Each
one-second window is checked to have begun before expiry; a severely overloaded
runner fails that precondition visibly rather than claiming a false race. The committed-data integration/repeated_soft_close_spec.rb
observes two successive real windows, roughly 32 seconds apart, with independent
sessions verifying each commit and no intervening clock or deadline manipulation. Ordinary expired-state fixtures explicitly alter stored
deadlines; these are fixture construction, not claims that actual time advanced.

**Read first:** ADR-005, Auction#place_bid!/#set_maximum!/#close!, AuctionClock,
AuctionDeadline, AuctionCloser and bin/auction_closer. Study
integration/concurrent_closing_spec.rb, models/soft_close_spec.rb and
models/auction_deadline_spec.rb; scripts/smoke-closing demonstrates separate Rails
processes, real HTTP requests and two independent closing processes.

**Limits and interview discussion:** explain why scheduler delay is harmless to
eligibility but harmful to status freshness; why uncached wall time must follow
the lock; why a proxy contest extends only once; and why winner is copied from the
settled leader rather than recomputed from maxima. Discuss host clock changes,
hot-row contention, duplicate discovery, connection pressure and the lack of a
materialization SLA. Phase 5 must persist replay outcomes so a lost HTTP response
cannot cause another bidding contest or extension.

## Client command idempotency — Phase 5

**The classic failure:**

```text
client -- POST bid / key X --> server -- COMMIT --> PostgreSQL
client <---- response lost --- server
client -- retry key X -------> server
```

A transaction made the first mutation atomic. It did not tell the client that the
commit happened. Without retained request identity, a retry is another evaluation:
it can repeat effects or reject a command that already succeeded. Searching for the
same user/amount is not idempotency: a different user intention can have identical
values. The client supplies the key so it knows which identity to retry after losing
the response. A key generated only in the lost server response cannot help.

**The actual protected request flow:**

```text
HTTP request
    |
parse required Idempotency-Key, parameters and actor
    |
build canonical semantic SHA-256 fingerprint
    |
BEGIN
    |
claim / resolve PostgreSQL (actor, operation, key digest)
    |
    +-- existing + matching + completed --> replay stored status/body
    |                                      no Auction lookup, lock or clock
    |
    +-- existing + different fingerprint -> 409 conflict
    |                                      no auction mutation
    |
    +-- newly owned processing row
                    |
                lock/reload auction
                    |
           PostgreSQL clock_timestamp()
                    |
              domain validation
                    |
          complete bidding/proxy/extension
                    |
          store public response snapshot
                    |
                  COMMIT both
```

The scope includes actor and operation, not auction. Alice reusing place_bid/key X
for another auction is a conflict; using X for set_maximum_bid is a separate scope.
Actor is still a supplied user ID and therefore not authentication. Canonical data
contains v1, operation, normalized auction/actor IDs and typed amount arguments.
JSON whitespace/key order is irrelevant. The fingerprint prevents one identity
from silently changing its meaning; no old private payload is returned on conflict.

**Why one transaction matters:** committing ownership first creates a zombie key
if the process crashes. Committing the bid first creates a gap where its outcome
has no replay record. Here the uncommitted claim, full auction mutation and terminal
snapshot commit together. Auction methods create savepoints under the wrapper's
outer transaction. RELEASE SAVEPOINT is not an independent durable commit: a later
snapshot failure still rolls back all bids, private maxima, leader and extension.
Expected domain rejections roll back the domain savepoint, then store a terminal
public error in the outer transaction. Unexpected errors propagate and remove the
claim with rollback; a retry can try again.

**How duplicates coordinate across processes:**

```text
Owner A                            Duplicate B
INSERT processing key X            INSERT same unique scope/key
owns key                           waits on PostgreSQL uniqueness
lock auction; decide; settle       (has not evaluated Auction)
store outcome; COMMIT               INSERT reports conflict
                                   read completed snapshot; replay

Alternative: A rolls back           B's INSERT can now own X
                                   execute once; store; COMMIT
```

A Ruby mutex or process-local cache would coordinate only one API process. Redis
would not share this database commit boundary. The composite SQL unique index and
ON CONFLICT DO NOTHING avoid a check-then-insert race and an aborted transaction
from rescuing a uniqueness violation incorrectly.

**Hammerfall examples:** Bob's manual 200 triggers Alice's automatic 210, creating
sequences 2 and 3 and one +90 extension. Ten requests with that same key all return
Bob's original accepted Bid ID/sequence; only one contest occurs. Alice's 300->500
maximum increase changes priority once and may extend without a visible row; replay
never changes priority or duration again. A new key repeating max 500 is a new
command and may be a domain no-op. It is not marked Idempotency-Replayed.

If Bob's successful response was lost, then Alice bids more and the auction closes,
Bob's retry still returns the saved 201 response. It does not rerun expired-window
checks and is not a current-state query. GET Auction shows the current leader/winner.
Likewise, a retained bid_too_low rejection reports its original minimum, even after
price rises. Missing header or malformed request never establishes ownership;
known domain 422 and execution-time 404 do. Arbitrary internal/DB failures do not
become permanently cached 500s.

**Response privacy:** store only the public Bid presenter or amount-free maximum
acknowledgment and error envelope. Never store record.attributes or raw request JSON.
Only key/fingerprint digests enter the idempotency table. Keys and hidden ceilings
must not appear in added logs. Representation privacy still does not authenticate
actors or protect plaintext database access.
An unkeyed SHA-256 digest can still expose a weak client key to a database thief
through offline guessing. HMAC would improve that property, but existing
unversioned rows and secret rotation require a replay-preserving migration.

**Retention bounds the promise:** seven days by default marks when a completed row
may be pruned. An expired-but-present record still reserves its key; only physical
prune permits reuse. The bounded manual task uses DB time and SKIP LOCKED. Automatic
scheduling, storage volume and client retry horizons need future operational work.
CURRENT_TIMESTAMP is fine for conservative retention; it remains wrong for an
auction deadline decision after waiting on the auction lock.

**Read first:** ADR-006; app/services/idempotent_bidding.rb;
app/services/idempotency/executor.rb; app/models/idempotency_record.rb under apps/api.
Follow controllers through claim, domain savepoint, public snapshot and outer commit.
Study requests/idempotency_spec.rb for lost response/changed state/closed replay and
privacy, integration/concurrent_idempotency_spec.rb for real duplicate/conflict/rollback
sessions, models/idempotency_record_spec.rb for prune/reuse, and scripts/smoke-idempotency
for ten requests across two independent APIs. See progress.md for actual sabotage,
repetition and live evidence.

**Guarantees and limits:** retained matching keys do not reevaluate auction commands;
mutations and snapshots share one commit. Extra indexed records/JSON and claim/write
round trips lengthen transactions; no measured throughput/latency improvement is
claimed. Duplicate waiters can consume connections. Expiry, authentication changes,
future API serialization changes and non-idempotent internal callers are boundaries
that need explicit treatment. Phase 6 should preserve pending keys across uncertain
network outcomes and generate a fresh key only for a genuinely new intention.

## Browser correctness — Phase 6

**Problem:** displayed state is not necessarily current state. A successful bid is
not necessarily the current leader. A network failure is not proof of rollback.
A naive frontend optimistically changes price/leader, closes at local zero and
creates a new key for each retry. Each shortcut contradicts a backend guarantee.

**The implemented boundary:** React displays typed public GET state and submits
intentions. Rails/PostgreSQL owns decisions. The listing and detail use one REST
client and explicit shapes. The application shell holds demo identity and one
pending command; individual screens own their reads and local form input. No
second auction engine, BFF, global auction store or event transport was introduced.

**Lost response timeline:**

```text
Browser                             Rails/PostgreSQL
Save session intention K1 + P
POST bid K1 ---------------------->
                                    lock + validate + settle
                                    COMMIT bid + extension + outcome
            X response lost
"Was this processed?"
Reload tab; recover K1 + P
Retry SAME K1 + P ----------------->
                                    replay retained outcome
<---------------- original result
Clear pending intention
GET auction + history ------------>
<---------------- current public state
```

Changing the amount under K1 would cause 409. Creating K2 for a transport retry
could cause another real command. Therefore pending/ambiguous intentions are
immutable and block actor changes and both bidding forms. A synchronous ref guards
two clicks before React updates. sessionStorage is written before transmission;
if it is unavailable, transmission is blocked. It temporarily contains the caller's
own pending maximum, never another user's private data. Resolved commands are
removed. An explicit two-step abandonment warns that it cannot cancel server work.
A browser abort is treated like network ambiguity, not server cancellation.

**Command outcome versus auction outcome:**

```text
Browser sees price 100 / leader Alice
Bob submits manual 200 / key B1
Rails accepts Bob 200 and settles Alice's counter at 210 in one transaction
201 returns Bob's accepted bid of 200
GET returns price 210 / leader Alice
UI: "Your bid was accepted" and "Current leader · Alice"
```

There is no contradiction. The command was accepted; it did not promise leadership.
Another command may also commit between POST and GET. A recovered old response can
be older still. Current GET data drives the page, never the command body's amount.
Only closed status plus public winner_id supports a final winner label.

**Stale rejection is ordinary interaction:** a page hints minimum 310, another
bidder raises price to 400, and submitting 310 returns bid_too_low/minimum 410.
The form explains that rejection and labels safe error details as values at the
server's decision, clears the terminal intention and refreshes auction/history.
The user can create a new intention. The frontend neither silently raises the amount
nor automatically retries it. Conflict 409 is a client-intention problem, never a
reason to quietly generate another UUID.

**Countdown is presentation:** X-Server-Time estimates app-clock/browser offset,
not PostgreSQL decision time. Network delay and host clock differences remain.
The isolated countdown ticks without rerendering the whole auction each second;
at zero it shows Checking status and refreshes once per effective deadline. It
never changes status to closed, infers a winner, or edits ends_at. A returned
extension restarts the display. With a delayed closer, manual/focus refresh may
still be needed to see finalization. The server may accept or reject irrespective
of a browser estimate; only clearly terminal/non-active states hide new commands.

**Exact input:** split the decimal string into euros and fractional digits, pad
one fractional digit, and build bounded integer cents. `10.999` fails; it is never
rounded into a different bid. EUR formatting is display-only. Client validation
checks shape/bounds, while price, binding-maximum rules and deadlines stay in Rails.

**Read races:** a slow GET started before a later refresh must not overwrite that
later result. Abort controllers and generation guards reject stale completions.
Pagination uses authoritative sequence, preserving equal-price rows. Separate
auction/history requests still are not one database snapshot; do not infer a winner
from the last loaded history row. Refresh resets history to its first page.

**Why Phase 7 is needed:** this phase refreshes only on initial load, explicit
request, return to a visible tab, countdown zero and terminal commands. Other
bidders' activity can remain unseen between those points. No Connected/Realtime
badge or aggressive polling conceals that gap. Phase 7 adds actual server-pushed
updates and reconnect recovery while retaining command identity and server authority.

**Read first:** ADR-007, docs/frontend.md, lib/api/client.ts, lib/intentions.ts and
components/auction/session.tsx under apps/web/src. Then follow auction-detail.tsx,
bidding-panel.tsx and presentation.tsx. Study commands.test.tsx for response loss,
replay, terminal errors, actor changes and storage failure; reads.test.tsx for
stale GETs/pagination; presentation.test.tsx for fake-time boundaries/privacy;
and e2e/auctions.spec.ts for a real commit whose response is intentionally dropped.

**Guarantees and limits:** stable retained intentions make explicit retries safe
under the backend contract. Demo IDs are not authentication. Storage can be lost,
copying tabs may copy commands, the one-hour client retry horizon relies on a local
clock, and no cross-tab coordination exists. No instant freshness, consistent
multi-query snapshot, production security, capacity or accessibility certification
is claimed. Explain these limits alongside the successful recovery timeline in
an interview, rather than calling the entire UI strongly consistent.

## Phase 7 — Invalidations, authority and missed messages

A WebSocket is a transport, not an authority:

```text
WebSocket: something changed (revision 12)
REST:      this is the public state now (perhaps revision 14)
PostgreSQL: this is what actually committed
```

Full snapshots put more sensitive data and domain interpretation into messages.
Their arrival order can regress a browser, and a proxy contest could appear half
finished. A tiny revision hint avoids that contract. `public_revision` orders every
public mutation; bid sequence misses cancellation/closure/protection-only extension.
`updated_at` can tie and is unsuitable for separating private writes from public
changes. Private-only maxima emit nothing, including no public timestamp/revision
change, so subscription activity does not expose that private action.

The locked transaction updates state and revision together. Publishing before
commit lets a subscriber GET old state or see a phantom action that rolls back.
Rails transaction callbacks defer publication until the outermost commit, including
when the command runs in a savepoint. The database still cannot atomically commit
and complete a later external broadcast:

```text
lock -> mutate + revision -> COMMIT -> [crash gap] -> broadcast
                                  authoritative     best effort
```

Action Cable/NOTIFY is ephemeral: disconnected consumers have no retained messages
to replay. Reconnection therefore reads current REST state. It need not reproduce
each missed intermediate auction display. Subscribe-confirm-refresh also closes
the initial GET-to-subscribe race:

```text
GET 10 -> commit 11 missed -> subscription confirmed -> GET 11
connected -> disconnect -> commits 12,13 -> reconfirm -> GET 13
```

Out-of-order/equal hints are harmless when ignored at or below the highest known
revision. Bursts become serial coalesced REST reads, and older REST snapshots cannot
regress displayed auction state. An unmet unchanged hint has bounded retries;
transport health and REST errors are different signals.

A public event cannot confirm your command: another bidder may have caused it, and
an accepted command may have been immediately outbid. Keep the opaque intention
until a terminal response or safe idempotent replay resolves it. This remains true
when an invalidation arrives before a lost command response. See realtime.md for the
commit-to-Cable diagram and the exact protocol, and progress.md for sabotage evidence.

## Phase 8 — Asynchronous public hints and read-only sweeps

**Problem.** Direct after-commit Cable work tied the API process to broadcast
latency; Phase 8 also needs useful background jobs and scheduled consistency
checks. A naive queue call inside the bid transaction could announce uncommitted
or rolled-back state and lengthen the hot auction lock. Treating Redis as auction
truth would make Redis loss a correctness failure.

**Chosen path.** The existing locked mutation commits state and public revision.
The outermost callback enqueues only auction ID and revision. Sidekiq reads the
current PostgreSQL revision and broadcasts the unchanged three-field hint through
the PostgreSQL Cable adapter. Browser confirmation, reconnect and higher hints
still trigger REST. Delayed and duplicate jobs may cause redundant GETs but cannot
regress public revision or decide a bid. An API process, Redis, worker and Cable
process can all be separate; the cross-process script verifies this path.

```text
auction transaction → COMMIT → enqueue to Redis → Sidekiq reads PostgreSQL
                                     → Cable hint → browser REST GET
                         ^
                unprotected commit/enqueue gap
```

**Limits.** A crash or Redis outage before enqueue can permanently lose a hint.
A worker crash, duplicate delivery or out-of-order jobs are tolerated only because
the job is a harmless public invalidation and the browser reads current REST.
Sidekiq's bounded retries and Dead set need operator attention; Redis AOF does not
create a transactional event log. A client may stay stale until another refresh
trigger. Idempotent command replay and PostgreSQL winner/deadline authority are
unchanged. Phase 9 is required before claiming durable publication.

The periodic reconciliation framework scans one bounded SQL statement per page,
checking stored price/current leader/final winner against latest accepted Bid.
It logs drift and never repairs or updates Redis. Naively writing a guessed repair
would risk corrupting authoritative history. It has no projection to compare until
Phase 11 and no repair policy until Phase 12. Duplicate scans only repeat logs.

**Read first:** ADR-009, `auction_publication.rb`, `auction_changed_job.rb`,
`reconciliation_sweep_job.rb`, the committed-publication and job specs, then the
Sidekiq/Redis runbook. Explain the commit/enqueue gap, harmless duplicate/reorder
behavior, and the distinction between a read-only PostgreSQL check and future
projection repair.

## Phase 9 — Transactional outbox

**Problem.** Phase 8 committed a bid and then asked Redis to enqueue its public
hint. If the API died between those steps, PostgreSQL retained the bid but no
process retained the intention to notify. Redis outage had the same loss window.

**Chosen path.** The locked auction transaction saves the domain change, public
revision and a versioned public-only outbox row together. A separate publisher
later finds committed pending rows, claims them with `SKIP LOCKED`, enqueues the
Sidekiq job and records acknowledgment. The domain transaction never waits for
Redis. Rollback removes state and intent; private-only maximum changes, no-ops,
rejections and idempotency replay create no new public row.

```text
auction transaction: state + revision + outbox intent → PostgreSQL COMMIT
publisher later: committed intent → Redis enqueue → mark outbox published
worker: current PostgreSQL revision → Cable hint → browser REST GET
```

**Why duplicates remain possible.** Redis may accept the job immediately before
the publisher dies. PostgreSQL then has no acknowledgment, so another publisher
tries again. The two jobs may both run, and different rows may arrive out of
order. The job reads the current PostgreSQL revision and only sends a public
refresh hint. This is at-least-once enqueue while intent is pending, not
exactly-once Cable delivery. Once acknowledged, Redis loss, Dead-set exhaustion
or Cable failure can still lose the hint; browser REST recovery remains essential.

**Read first:** ADR-010, `Auction#persist_public_change!`, `OutboxEvent`,
`OutboxPublisher`, `transactional_outbox_spec.rb`, then the Phase 9 ExecPlan's
live crash/outage evidence and the runbook. In an interview, distinguish the
atomic PostgreSQL commit from the later queue acknowledgment and explain why
the latter cannot certify browser receipt.

## Phase 10 — Kafka after the outbox

**Problem.** A direct post-commit Kafka send would recreate the API crash gap
that Phase 9 closed. A broker delivery report also cannot prove a consumer
effect, and an offset commit before that effect could lose audit work.

**Chosen path.** Each public revision stores one public domain snapshot on its
existing outbox row inside the auction transaction. Sidekiq and Kafka publishers
read the row independently. The Kafka publisher claims a due row, sends with
auction ID as partition key, waits for a broker report, then acknowledges in
PostgreSQL. The audit group validates v1 JSON, commits receipt and public audit
entry in one PostgreSQL transaction, then commits the Kafka offset.

```text
auction transaction: state + public revision + public outbox snapshot → COMMIT
  ├─ Sidekiq enqueue → current-revision Cable hint → browser REST GET
  └─ Kafka delivery report → Kafka outbox ack → audit receipt + effect → offset commit
```

**Failure reasoning.** Kafka outage leaves a pending row without changing a
bid. Publisher death after broker delivery can send the same event ID twice;
consumer death after its database effect can replay it. The unique receipt
suppresses repeat effects. A different payload with the same ID is poison.
Concurrent publishers may reorder same-auction revisions despite a stable
partition key; the audit labels stale/gap arrival without regressing truth.
Unknown schema/version records stop the group at an uncommitted offset until an
operator reviews and explicitly resets it. Replay is limited by broker
retention and encounters unresolved poison again.

**Limits and interview explanation.** `kafka_published_at` is broker
acknowledgment, not consumer or browser receipt. Kafka is a propagation
channel, not an auction decision engine or backup. The local broker is one
plaintext replica with no production availability claim. Read ADR-011,
`KafkaOutboxPublisher`, `KafkaAuditConsumer`, `kafka_outbox_spec.rb`, the Phase
10 ExecPlan's live failure evidence and the Kafka runbook. Explain why database
receipt plus offset order is at-least-once safe without claiming generic
exactly-once semantics.

## Phase 11 — A disposable public read model

**Question.** How can a fast read coexist with PostgreSQL authority when Kafka
delivery can repeat or arrive out of order? A separate projection consumer
validates the committed public event, atomically compares its revision with
the Redis key, writes only a higher revision, and commits the Kafka offset
after the write. Equal public data is a duplicate; older data is stale;
same-revision/different-data stops for investigation. A process dying after
the write simply replays a duplicate. None of these paths participates in a
bid transaction.

```text
PostgreSQL auction + public outbox → Kafka → projection group → Redis key
         ↑ current ordinary GET                       ↓ eventual public GET
         └──────────── fallback on missing/bad/unavailable Redis ─────────┘
```

**Question.** Why is Redis loss recoverable without treating Kafka as a
backup? A Kafka offset may already be committed, retained history may be
incomplete, and older rows predate the event snapshot. The manual rebuild
seeds current public state from PostgreSQL through the same revision guard.
Replay of older Kafka revisions cannot lower that seed. A valid but stale key
is still a possible eventual result; the exposed age is diagnostic, not a
freshness SLA. The ordinary GET remains the browser's authoritative recovery
read. Read ADR-012, `AuctionPublicProjection`, `KafkaProjectionConsumer`,
`redis_projection_spec.rb` and the projection runbook. Explain the crash,
total-loss, privacy and poison boundaries without claiming exactly-once or
automatic drift repair.

## Phase 12 — Detecting and repairing a derived projection

**Problem.** Redis may be missing, stale or corrupt even while Kafka delivery
and PostgreSQL bidding remain healthy. Checking only projection age or replaying
Kafka cannot establish current auction truth. The checker reads the PostgreSQL
public revision and exact public presenter fields, validates Redis, then
classifies the difference. It seeds missing and valid lower revisions through
the existing atomic Redis writer. Equal identical state is a no-op; equal
conflicts, ahead Redis revisions and corrupt values stay for operator review.

**Race.** PostgreSQL snapshot N can become stale while Kafka writes N+1. A
direct `SET` by repair would regress Redis; the Lua revision guard returns
`stale` instead. If repair writes first, later Kafka delivery advances the
key. Two reconcilers can repeat a repair, and a crash after Redis write can
retry safely. None of this makes Redis an authority or promises exactly-once
reconciliation.

**Scheduled load.** The PostgreSQL consistency sweep remains read-only and
separate from the projection checker. Each job reads at most 100 auction IDs
within a captured maximum ID. A PostgreSQL maintenance lease for each scan
type prevents periodic ticks from growing overlapping chains. Jobs renew a
database-clock lease and atomically advance its cursor before enqueueing a
successor. A worker dying after cursor advancement can lose that handoff;
lease expiry lets a later tick start again at ID zero. No auction transaction
or row lock is held across the scan. A manual tokenless job can overlap by
operator choice.

**Limits.** Valid stale state may persist until the next successful scan;
corrupt/conflicting/ahead state needs review. PostgreSQL outage prevents safe
comparison, and Redis outage delays repair without changing bids. Per-batch
structured log counts are operational evidence, not a Prometheus exporter or
freshness guarantee. Read ADR-013, `AuctionProjectionReconciler`,
`ReconciliationLease`, the Phase 12 integration specs and the reconciliation
runbook. Explain why expiry and cursor fencing bound maintenance work while
the database remains the only auction authority.

## Phase 12.5 — A public snapshot is more than a field list

An envelope can have every expected key and type while claiming a closed
auction without `closed_at`, a winner unlike its leader, or a price below the
start. `PublicAuctionSnapshot` validates those relationships once for Kafka
decoding and Redis reads. A matching Redis digest proves only that the stored
bytes are self-consistent, so reconciliation still treats an impossible value
as corrupt. The outbox now timestamps insertion using PostgreSQL wall time;
that differs from the earlier locked decision time, transaction start, commit,
publisher acknowledgment and Redis write. None is a bid-ordering clock.

## Phase 12.5 — Publisher locks and delivery ambiguity

Both publishers hold an outbox row lock and PostgreSQL connection while waiting
for their external dependency. `SKIP LOCKED` lets another publisher advance
different rows, but the two paths temporarily exclude each other on one row.
The transaction makes process death or database acknowledgment failure leave
that row pending; a delivery accepted before the failure may repeat with the
same event identity. Sidekiq's duplicate job reads the current revision, and
Kafka consumers use receipts/revision guards. This simple protocol has an
operational connection cost. A short claim protocol would need durable expiry
and ownership fencing; the Phase 12.5 review retained the current design until
later load measurements justify that complexity.

The final review also tested deadline ordering as a logical chain rather
than two independent comparisons. `starts_at < ends_at` plus
`original_ends_at <= ends_at` still allows an original deadline before the
start. Normal commands set it correctly, but model, SQL and shared Kafka/Redis
validation now reject that impossible stored state explicitly.

## Phase 13 — Passive telemetry foundation

The tempting shortcut is to auto-instrument every library and use raw URLs,
SQL statements or message bodies as span attributes. Those fields can reveal
private bids or create unbounded series. Hammerfall uses bounded route names
and manually selected domain spans, with separate lock-wait and total bid
duration signals. The OTLP SDK exports on bounded background queues; the
auction command never asks Tempo or Prometheus whether it may proceed. A trace
helps explain the work that occurred, but a dropped span does not imply that a
bid failed. Read `lib/observability.rb`,
`lib/observability/http_middleware.rb`, `docs/observability.md` and the
Phase 13 ExecPlan.

## Phase 13 — Trace context is transport metadata, not event identity

The public outbox row now holds bounded W3C context alongside its stable event
UUID. Sidekiq middleware carries it outside job arguments, and Kafka headers
carry it outside the versioned snapshot. The worker and both consumers start
their own spans under extracted context; neither waits for the producer to
finish. A duplicate event may have multiple delivery attempts and spans while
remaining one durable event. Offset commits still follow PostgreSQL or Redis
effects. Live Tempo traces showed the HTTP command, both publishers, Sidekiq
worker/Cable broadcast and both Kafka consumers in one trace.

Exporter loss stayed outside those effects during a sustained Collector outage.
The Collector, Tempo, Prometheus and Grafana outage checks did not change bid
outcomes. Actual Prometheus names also showed why count gauges must omit the
OTel unit `1`: that unit produced an unwanted `_ratio` suffix. Local debug SQL
inlined private maximums, so development logs now use info level while request
parameter filtering masks whole command payloads. Run live integration specs against Redis
DB 1 when the development stack uses DB 0; separate PostgreSQL databases alone
do not isolate projection keys that share numeric auction IDs.

During final verification, Prometheus's historical `series` endpoint still
listed old `_ratio` gauge names after the corrected services restarted. An
instant query showed only the current count gauges. Compare current samples
and process identity before diagnosing a present naming defect from retained
history. The final distributed trace also had one short HTTP root and later
consumer child spans, so trace parentage did not imply a synchronous request
waiting for Kafka or Sidekiq.

## Phase 14 — Measuring load without changing auction authority

A 2xx-only load script would confuse successful reads, accepted bids and
idempotent replays, while treating expected stale bids as failures. The k6
harness classifies these separately and verifies committed PostgreSQL state
rather than trusting transport status. Fresh labeled fixtures, a read-only
warm-up, exact configuration and retained raw output make each local run
interpretable. Read `load-tests/README.md`, `load-tests/common.js`,
`apps/api/script/benchmark_verify.rb` and `docs/benchmarks/README.md`.

One hot auction intentionally serializes mutations. The 8/16/32/64 VU steps
held HTTP throughput around 84–101 requests/s while HTTP p95 rose from about
89–106 ms to 935 ms; the two 8-VU runs themselves varied. At 64 VUs, bid HTTP
p95 was 956 ms, but the auction-lock p95 histogram bucket was ≤25 ms and
rejected-bid processing p95 ≤100 ms. This points to work or queueing outside
the measured lock section, not a measured row-lock dominated HTTP tail.
Puma admission and DB checkout waits were not directly measured, so the next
investigation needs those boundaries rather than a guessed pool-size change.

At the same 16 VUs and read/bid loop, spreading across eight rows accepted
590 bids in 20 seconds versus 111 on one row, yet HTTP throughput fell because
accepted mutations perform more work than expected rejections. Compare useful
work, outcome mix and latency together. A 1,000-bidder final-ten-second burst
launched all VUs but reached the API process's 1,024-open-file soft limit:
28 server errors and 64 HTTP timeouts did not corrupt the auction. PostgreSQL
recorded 911 completed commands versus 908 successful/expected HTTP replies,
showing why timeout reconciliation must use command identity. A clean
600-bidder local burst and 500-socket fanout step are observations of this
Compose host, not capacity promises. Read the [Session 2 evidence](benchmarks/phase-14-session-2.md)
before drawing performance conclusions.

## Phase 15 — Locate queueing before tuning

Puma's `backlog` is a server-side queue sample, while a Rack timer begins
only after admission. On the 64-VU hot diagnostic run, backlog stayed near
58 requests, Active Record's actual blocking queue wait had no samples,
checkout p95 was ≤1 ms and auction-lock p95 was ≤10 ms. This supports
admission delay as the major local HTTP-tail contributor without pretending
to have a per-request pre-Rack timer. The CPU profile showed development
file checks consuming 13.3% inclusive CPU samples; that is a local Compose
runtime cost, not a reason to alter auction serialization. Read the
[Phase 15 profiling report](benchmarks/phase-15-session-1.md) and its raw
links before changing Puma, pool, SQL or FD settings.

The [Phase 15 controlled comparisons](benchmarks/phase-15-session-2.md)
show why a larger request pool was not adopted: five threads with three DB
connections introduced blocking pool waits, while five DB connections
removed those waits without improving accepted work. Disabling development
request reloading raised local service rate but did not reliably reduce the
HTTP tail or Puma backlog. Telemetry-off runs were faster, but operational
visibility was retained. A later identical baseline shifted enough to rule
out precise capacity or tuning claims from a single window.
The [final Phase 15 review](benchmarks/phase-15-final.md) also records why
increasing the connection pool removed a measured queue without improving
the whole HTTP path. A queue can migrate to a new resource when concurrency
is raised; compare accepted work, latency and resource cost before retaining
a configuration change.
