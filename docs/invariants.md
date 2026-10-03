# Invariants

## Implemented through Phase 6

Unless explicitly marked SQL, these guarantees apply to concurrent calls through
the documented domain entry points at PostgreSQL READ COMMITTED isolation.
Privileged validation-bypassing writes remain outside the workflow contract.

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| Money is positive, bounded integer cents; fractional input is never silently truncated | MinorUnitsValidator before casting; SQL bigint/range CHECKs | auction_spec.rb, bid_spec.rb, domain_constraints_spec.rb |
| Every accepted bid references one existing auction and bidder | SQL NOT NULL and foreign keys; model validations | bid_spec.rb, domain_constraints_spec.rb |
| New auctions are draft; only documented edges and preconditions are allowed | Auction lifecycle methods and managed-field validation | auction_spec.rb transition matrix, auctions_spec.rb |
| Only active auctions within starts_at <= now < ends_at accept bids | place_bid! | bid_spec.rb, bids_spec.rb |
| Manual bids meet starting price or price + increment; automatic rows may use a final partial increment or equal-price priority tie | place_bid! | bid_spec.rb, bids_spec.rb |
| Price equals starting price with no bids and the last accepted amount otherwise | create_draft!, edit_draft!, transactional place_bid! | auction_spec.rb, bid_spec.rb, injected-failure rollback example |
| Rejected operations persist neither bid nor price changes | validation before writes and transaction rollback | bid_spec.rb, bids_spec.rb |
| Accepted bids cannot be edited or destroyed through normal model operations | Bid readonly?; no mutation API | bid_spec.rb |
| Auction terms freeze after draft; cancellation cannot discard accepted bids | Auction validations and cancel! | auction_spec.rb |
| At most one stored winner, and none outside closed state | One nullable winner_id; SQL FK and status CHECK | auction_spec.rb, domain_constraints_spec.rb |
| Close copies the explicit priority-resolved leader, or no winner with no bids | close!; repeated close is a no-op | auction_spec.rb, bids_spec.rb |
| History has unique increasing auction-local sequence, excluding client ordering | Locked MAX(sequence)+1; SQL positive/NOT NULL/unique index; sequence pagination | concurrent_bidding_spec.rb, domain_constraints_spec.rb, bids_spec.rb |
| Fresh validation and price/history mutation serialize per auction | SELECT FOR UPDATE before decisions; same lock for lifecycle/draft commands | concurrent_bidding_spec.rb stale waiter, same amount, many bidders, lifecycle and close cases |
| Other auctions can progress while one is locked | Independent aggregate rows | concurrent_bidding_spec.rb independent-auction case |

The API returns the persisted winner; it does not promote an active leader into a
winner. The frontend renders that public state and never promotes a leader locally.
Actual files are mapped in [code-map.md](code-map.md). Tests reside under
`apps/api/spec/models`, `spec/requests`, and `spec/integration`.

## Master requirements and remaining work

All 15 original master invariants remain requirements. Their current status is:

1. **Closed auctions cannot accept a new bid:** enforced under the shared auction lock;
   DB time after lock also forbids late bids while status still says active.
2. **Same scoped idempotency key cannot repeat a bidding command:** implemented
   for HTTP bid/max endpoints while the record is retained; SQL ownership and
   terminal response persistence share the auction mutation transaction.
3. **Every accepted bid belongs to exactly one auction:** enforced structurally
   by SQL NOT NULL/FK.
4. **At most one authoritative winner:** one winner reference; current close and bid
   commands share the auction lock and select committed history.
5. **Deterministic authoritative accepted-bid ordering:** enforced by auction-local
   sequence under the lock and SQL uniqueness. No global ordering is claimed.
6. **Client timestamps cannot determine authoritative ordering:** clients cannot
   set bid timestamps or sequence; the locked server assigns sequence.
7. **Authoritative visible winner agrees with PostgreSQL:** ordinary API GET
   serializes the stored winner. The explicit Phase 11 Redis read may lag and
   reports its derived source.
8. **Automatic bid maxima are private:** explicit public presenters/acknowledgements
   omit maxima/priority/origin; request/SQL/inspection filters are tested. Phase 20
   derives actors from authenticated sessions and rejects supplied bidder IDs;
   operators with database access can still inspect plaintext maxima.
9. **Concurrent requests cannot lose updates:** enforced by the row lock and atomic bid/price writes.
10. **Closure and bid acceptance serialize correctly:** current commands share a row lock;
    post-lock DB time, autonomous closer and atomic extensions are implemented.
11. **Committed public mutations retain publication intent:** Phase 10 stores a
    public domain snapshot in the Phase 9 outbox row, atomically with the public
    revision. Redis and Kafka publishers have independent acknowledgments.
12. **Duplicate delivery does not duplicate domain effects:** Sidekiq jobs read
    current revision and only request REST refresh. The Kafka audit consumer
    commits one receipt and audit effect per event ID before offset commit.
13. **Read-model inconsistency is detectable:** Phase 11 exposes source,
    revision and age; Phase 12 compares a validated Redis projection with
    current PostgreSQL public fields in bounded scheduled scans.
14. **Read-model inconsistency is repairable:** Phase 12 seeds missing and
    valid lower-revision Redis keys from PostgreSQL through the atomic
    revision guard. Conflicting, corrupt and ahead keys require review.
15. **Redis or Kafka loss cannot invalidate authoritative state:** both are
    downstream transports; outage preserves committed PostgreSQL state and
    pending transport intent until successful acknowledgment.

The dedicated concurrency group commits data and checks real independent PostgreSQL
sessions. The ordinary suite keeps transactional wrappers. Removing locks must fail
the concurrency suite; actual mutation/repetition results are recorded in progress.md.

## Phase 11 Redis projection invariants

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| Derived events cannot regress a higher public revision | Atomic Redis Lua revision comparison; stale events skipped | `redis_projection_spec.rb`; live stale/replay and sabotage checks in Phase 11 ExecPlan |
| Equal data is idempotent; equal revision with different data stops | Public digest comparison before offset commit | Focused conflict/duplicate tests; live duplicate and crash replay |
| Projection loss cannot erase auction truth | Commands and ordinary GET use PostgreSQL; eventual read falls back | Focused outage tests and live Redis stop/full-loss campaign |
| Rebuild preserves public privacy and current state | Presenter allowlist and same atomic revision rule | Rebuild privacy regression; live PostgreSQL seed and replay |

## Phase 12 reconciliation invariants

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| PostgreSQL remains auction authority | Checker reads PostgreSQL public revision/fields; Redis and lease are maintenance inputs only | Redis/PostgreSQL outage campaign and bid-under-lease integration test |
| Old repair cannot regress newer Kafka delivery | Existing atomic Redis revision/digest writer; no direct repair SET | Real Kafka race in both orders, concurrency tests and stale-overwrite sabotage |
| Ambiguous Redis state is never guessed away | Equal conflicts, ahead state, malformed envelope/digest trigger operator review without key mutation | Deliberate corruption and operator-log tests; equal-conflict sabotage |
| Repeated and concurrent repair is safe | Atomic duplicate/stale handling; idempotent current-state seed | Two-reconciler, repeat and crash-after-write tests |
| Scheduled scans cannot multiply indefinitely | PostgreSQL lease per scan type, token/cursor fencing, DB-clock expiry and 100-row pages | `reconciliation_lease_spec.rb`, cursor-fence sabotage and Compose scheduler smoke |
| Failed or crashed scheduled ownership is recoverable | Expired lease reclaimed; replacement restarts at ID zero; final page releases | Abandoned owner, post-advance crash and completion tests |
| A reclaimed lease receives fresh expiry after a database row-lock wait | Conflict update samples `clock_timestamp()` after acquiring the lease row | `reconciliation_lease_spec.rb` delayed-claim test |

Normal accepted sequences are contiguous while history is immutable, but the public
contract promises monotonicity, not gaplessness after privileged changes.

## Phase 12.5 public event integrity

Kafka decoding and Redis projection reads share `PublicAuctionSnapshot`: exact
public fields, bounded money, ordered deadlines, price floor, closed-at iff
closed, and winner matching the leader only on closure. Invalid derived state
stops consumer progress or triggers operator review without changing auction
truth. New outbox occurrence timestamps use PostgreSQL insertion wall time;
historical rows retain their old transaction-start value. Active Record treats
committed event identity, payload and occurrence time as readonly while allowing
publisher acknowledgments. SQL restricts new domain snapshots to known types
and JSON objects; historical invalidation-only rows remain allowed.

Both publishers acknowledge only after their external dependency accepts the
delivery. Each holds the outbox row transaction across that wait; a failed or
ambiguous delivery stays retryable, and a crash after acceptance can duplicate
the same immutable event. Kafka and Sidekiq retry/ack fields are independent,
although `SKIP LOCKED` temporarily defers the other path on a shared row.
Other due rows remain eligible. This publication protocol cannot change
authoritative auction state; its connection/lock occupancy is an operational
cost, not a production throughput guarantee. See [ADR-010](adr/010-transactional-public-outbox.md)
and [ADR-011](adr/011-kafka-domain-events.md).


## Phase 3 proxy invariants

| Invariant | Enforcement | Evidence under apps/api/spec |
| --- | --- | --- |
| One current instruction per auction/bidder, positive bounded ceiling and unique positive priority | SQL FK/NOT NULL/CHECK/unique indexes | integration/maximum_bid_constraints_spec.rb |
| Ceilings are binding: increase only; repeat is a no-op; no cancellation | Auction#set_maximum!, MaximumBid destruction guard | models/maximum_bid_spec.rb, requests/maximum_bids_spec.rb |
| Equal ceilings favor earlier commitment to that ceiling; increases reset priority | Locked priority allocation and ProxyResolver comparison | models/maximum_bid_spec.rb, integration/concurrent_maximum_bidding_spec.rb |
| Automatic rows never exceed binding ceiling | ProxyResolver clamps winner and exhausts loser at its ceiling | deterministic matrix and 80-operation invariant stream |
| Price never decreases; sequences strictly increase; equal-price visible rows are legal | Ordered synchronous resolver emissions | both concurrency groups and invariant stream |
| Final public price/explicit leader agree with complete visible history; winner stays nil while active | Final auction save inside shared transaction | deterministic, concurrency and request suites |
| Private instruction and all generated rows commit or roll back together | Savepoint plus auction row lock | real SQL failure after two generated rows in concurrent_maximum_bidding_spec.rb |
| Public JSON/errors/logs disclose no unused ceilings or automatic-origin metadata | Presenters/acknowledgement allowlists and Rails filters | requests/maximum_bids_spec.rb actual JSON/debug log assertions |

Phase 2's strict increase between every pair of visible bids is deliberately
refined to non-decreasing amounts. Manual entry minimums remain unchanged. The
leader is explicit, selected by durable priority rather than highest amount/ID.
A bidder's manual offer may exceed its own old private instruction; the ceiling
restriction applies to automatic offers. Public price can equal an exhausted
maximum by the required algorithm; no API labels it as that user's maximum.

## Phase 4 deadline invariants

| Invariant | Enforcement | Evidence under apps/api/spec |
| --- | --- | --- |
| Decision time is current DB wall time after serialization, never transaction start or cached SELECT | AuctionClock.now after reload(lock: true) | integration/concurrent_closing_spec.rb real pre-deadline transactions blocked past expiry; models/soft_close_spec.rb query-cache regression |
| Active is necessary but not sufficient; equality with ends_at is expired | AuctionDeadline.due? and locked eligibility | models/auction_deadline_spec.rb exact arithmetic; requests/bids_spec.rb stale active rejection |
| starts_at < original_ends_at <= ends_at, original end is non-null | SQL CHECK/NOT NULL, model/public-snapshot validation and frozen terms | integration/domain_constraints_spec.rb and deadline_constraints_spec.rb; models/soft_close_spec.rb; integration/kafka_outbox_spec.rb |
| One qualifying external commitment adds exactly 90 once; no extension for rejected/no-op actions | persist_bidding_action! only after accepted resolution | models/soft_close_spec.rb; exact 60.000/60.001 arithmetic tests |
| Proxy row count does not multiply extension; protection-only increases can extend | Both Auction entry points own extension | models/soft_close_spec.rb |
| Price, leader, visible bids, max/priority and deadline commit or roll back together | One savepoint and final auction UPDATE | integration/concurrent_closing_spec.rb SQL rejection of calculated extension for manual and maximum |
| Stale/duplicate closers recheck fresh state and do not shorten extended deadlines | Auction#close! uses the same lock/time protocol | integration/concurrent_closing_spec.rb both bid/max lock orders and eight closers |
| Closure emits no bid; winner equals final leader, including nil; closed_at never changes on repeat | close! and SQL null-safe equality, timestamp iff closed and >= end | deadline_constraints_spec.rb, concurrent_closing_spec.rb, soft_close_spec.rb |
| Repeated external actions may extend again in later windows without a cap | Pure extension arithmetic on effective end | integration/repeated_soft_close_spec.rb real roughly 32-second wait, no clock/deadline changes between commands |

These are decision-time guarantees, not a requirement that physical COMMIT occur
before ends_at. Deadline checks reject without lazy closure; scheduler lateness
only delays materialized status. Raw SQL, validation bypasses, host clock jumps and
multi-query snapshot consistency are outside the stronger workflow contract.

## Phase 5 idempotency invariants

| Invariant | Enforcement | Evidence under apps/api/spec |
| --- | --- | --- |
| One retained actor/operation/key identifies one semantic command | Transaction-scoped logical-key advisory lock across digest versions, composite SQL unique index on actor_id,operation,key_digest; canonical SHA-256 fingerprint | integration/concurrent_idempotency_spec.rb; integration/idempotency_key_rotation_spec.rb; requests/idempotency_spec.rb |
| Conflicting fingerprint never executes Auction logic | Executor resolves existing ownership first and returns 409 | concurrent_idempotency_spec.rb bid/max conflicting races |
| Matching replay cannot assign sequences, settle proxies, change max priority or extend | Return stored completed snapshot before Auction lookup | requests/idempotency_spec.rb; concurrent_idempotency_spec.rb ten-way duplicate cases |
| Success mutation and terminal outcome commit atomically | One Executor outer transaction; Auction requires_new savepoints | real SQL failure when persisting terminal outcome; owner rollback and waiting duplicate takeover |
| Completed replay never needs auction lock or deadline evaluation | Resolve key before IdempotentBidding block | concurrent_idempotency_spec.rb replay-after-close while another session holds the Auction lock |
| Failed infrastructure/internal execution leaves key retryable | Unexpected errors propagate and roll back outer transaction | concurrent_idempotency_spec.rb SQL failure; models/idempotency_record_spec.rb unexpected exception |
| Terminal domain rejection replays its original details | Persist public 422 snapshot after domain savepoint rollback | requests/idempotency_spec.rb changed minimum and expired-active then closed |
| Snapshot cannot disclose unused maximum or raw key | Public serializers/acknowledgements only; digest-only request identity | requests/idempotency_spec.rb actual database, replay/conflict JSON and debug-log assertions |
| Expired-but-present keys remain reserved; only expired completed records prune in bounded batches | PostgreSQL retention time and SKIP LOCKED prune command | models/idempotency_record_spec.rb |

These guarantees apply to protected HTTP commands (and IdempotentBidding callers),
not raw Auction method invocations without a client identity. They last while the
record exists and assume cryptographic digest collision resistance. HTTP actor
identity now comes from the authenticated session (ADR-016), while raw model
calls are internal, not HTTP authentication boundaries. Processing rows are normally uncommitted; direct SQL
can violate that workflow despite structural checks. No arbitrary 500 is cached.

## Phase 6 browser boundaries

These are client behavior guarantees, not replacements for the database invariants.

| Boundary | Implementation | Evidence under apps/web |
| --- | --- | --- |
| A new intention gets one key; ambiguity preserves actor/operation/amount/key | AuctionSession synchronous guard, sessionStorage, explicit retry | commands.test.tsx; real commit/drop/reload/replay E2E |
| Countdown cannot finalize an auction | AuctionTiming emits refresh only; UI reads status/winner from GET | presentation.test.tsx fake time; real closer browser scenario |
| Accepted bid does not imply leadership | Detail uses current_leader_id from fresh GET, no optimistic price/leader | commands.test.tsx; real proxy/stale rejection E2E |
| Public views render no private max/priority/origin | Public types and explicit cells; no broad object rendering | presentation.test.tsx extra-private-field fixture; real maximum browser scenario |
| Money input cannot silently round fractional cents | Decimal digit parsing and safe bounded integers | money.test.ts |
| Late read completion cannot overwrite a later refresh | Abort and generation guards | reads.test.tsx |

Phase 20 authenticates actor IDs and Phase 7 adds best-effort realtime hints.
Browser storage/clock loss and separate GET snapshots remain explicit limits.
See ADR-007 and ADR-016.

## Public observation ordering — Phase 7

A committed public mutation and its incremented public_revision are atomic. A
private-only maximum cannot change public_revision or public updated_at. Rollbacks,
replays and no-ops emit no new invalidation. The outbox row commits with the
revision; savepoint rollback removes both. A notification contains only type,
auction_id and revision. The browser cannot derive acceptance or winner from it,
and never replaces displayed auction state with an older REST revision.

## Phase 8 background-work boundaries (historical enqueue path)

| Boundary | Enforcement | Evidence |
| --- | --- | --- |
| Redis/Sidekiq failure cannot roll back a committed bid or idempotency outcome | Queue push occurs only after the outermost PostgreSQL commit; enqueue errors are logged and isolated | `spec/integration/public_revision_spec.rb` Redis enqueue failure; real Redis-stop HTTP/replay proof in progress log |
| Delayed, duplicate or reordered notification jobs cannot mutate auction state or send a regressed revision | Job reads current PostgreSQL `public_revision` and broadcasts only public ID/revision | `spec/jobs/auction_changed_job_spec.rb`; stale-revision sabotage |
| A failed broadcast is retryable without repeating domain work | Job raises to bounded Sidekiq retry; no auction write in job | Job spec and real RetrySet proof |
| Scheduled sweeps cannot repair or alter authoritative state | Read-only SQL comparison, fixed public-ID drift log and bounded cursor | `spec/jobs/reconciliation_sweep_job_spec.rb` corruption and pagination tests |

These are safety properties, not delivery or freshness guarantees. A crash after
commit but before enqueue was a Phase 8 loss window. Phase 9 now commits a
public-only outbox row with each revision. Rollback, private-only changes,
rejections, no-ops and idempotency replay leave no new public row. Publisher
retry can duplicate/reorder jobs, which read the current PostgreSQL revision.
Acknowledgment is successful enqueue only; Redis loss after it or exhausted
job retries can still lose a hint. A connected browser still needs REST recovery.

## Phase 9 outbox invariants

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| A public revision and publication intent commit or roll back together | `Auction#persist_public_change!` inserts before its savepoint exits; outer idempotency transaction owns the outcome | `transactional_outbox_spec.rb` rollback, failed insert and independent reader |
| One public intent per auction revision | Unique `(auction_id, public_revision)` and no insertion on private/no-op/replay paths | `transactional_outbox_spec.rb`, `public_revision_spec.rb` |
| Failure before enqueue does not discard committed intent | Pending rows discovered by independent publisher; persisted retry state | Phase 9 live process-kill and Redis outage evidence in `docs/plans/phase-09-execplan.md` |
| Publisher claims do not require a global lock | `FOR UPDATE SKIP LOCKED` on due rows | `transactional_outbox_spec.rb` concurrent connection examples |
| Duplicate enqueue cannot mutate auction truth | Job reads current revision and broadcasts only public hint | Acknowledgment-crash test and live duplicate-job evidence |

## Phase 10 Kafka invariants

| Invariant | Enforcement | Evidence |
| --- | --- | --- |
| Kafka failure cannot reject or change a committed command | Domain snapshot written in auction transaction; separate publisher runs after commit | `kafka_outbox_spec.rb`; live broker stop, bid and recovery in Phase 10 ExecPlan |
| Kafka ack follows broker confirmation | Delivery handle `wait` precedes PostgreSQL `kafka_published_at`; retry persists failure | Delivery-failure spec, live publisher SIGKILL and sabotage B |
| Duplicate/replayed event has one audit side effect | Unique receipt/event and audit rows in one transaction; offset follows commit | Consumer specs, live duplicate/replay and sabotage C/D |
| Stale, gap and poison events cannot change auction truth | Audit-only effect; strict envelope validation; poison offset remains uncommitted | Consumer specs and live poison/reset/replay evidence |

## Phase 18 local orchestration boundary

Kubernetes pod identity, Service routing, readiness and replica count have no
role in auction ordering, deadline, winner, idempotency or outbox identity.
The local API Deployment uses PostgreSQL readiness and process liveness;
replacement, manual scaling and bounded active SIGTERM preserved durable
command outcomes. A fresh replacement campaign observed one transient 502
among 40 reads, so process orchestration does not guarantee uninterrupted
responses. Same-key retry and current-state GET remain necessary. See
[ADR-014](adr/014-local-kubernetes-process-orchestration.md) and the
[Phase 18 final review](kubernetes/phase-18-final.md). This one-node local
proof is not a production availability claim.
