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

## Learning roadmap — not implemented

Add the problem, naive approach, failure modes, chosen implementation, guarantees,
limitations, source files, demonstrative tests, and interview explanation for each
subsystem when it is built:

- Auction closing and soft-close (Phase 4)
- Idempotency (Phase 5)
- WebSockets (Phase 7)
- Outbox (Phase 9)
- Kafka and consumer idempotency (Phase 10)
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
**Limits:** no FIFO/fairness, global ordering, clock synchronization, idempotency,
or throughput guarantee. A hot auction is a serialized resource. Independent
auctions can proceed concurrently; a long outer transaction delays lock release.

**Read first:** Auction#place_bid!, the sequence migration, BidPresenter, ADR-003,
and spec/integration/concurrent_bidding_spec.rb. The concurrency suite uses real
committed rows, independent PostgreSQL sessions and database-observed lock waits.
Transactional fixtures remain enabled elsewhere. Tests check outcomes, stale loaded
objects, rollback, lifecycle changes and independence, rather than mocking locks.

**Interview discussion:** explain atomicity versus isolation, why validation must
follow lock acquisition, why uniqueness is insufficient, how rollback affects
ordering, and why pessimistic locking trades simple correctness for hot-row queues.

## Automatic bidding — Phase 3

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
