# Invariants

## Implemented through Phase 5

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
winner. The static frontend still has no auction view or independent projection.
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
7. **Visible winner must agree with PostgreSQL:** API serializes the stored
   winner; real-time/frontend projection consistency is not implemented.
8. **Automatic bid maxima are private:** explicit public presenters/acknowledgements
   omit maxima/priority/origin; request/SQL/inspection filters are tested. No complete
   authorization secrecy exists with supplied unauthenticated bidder IDs.
9. **Concurrent requests cannot lose updates:** enforced by the row lock and atomic bid/price writes.
10. **Closure and bid acceptance serialize correctly:** current commands share a row lock;
    post-lock DB time, autonomous closer and atomic extensions are implemented.
11. **Committed bids eventually produce domain events:** Phase 9 onward; no outbox
    or event publication exists yet.
12. **Duplicate events do not duplicate downstream effects:** Phase 10 onward.
13. **Read-model inconsistency is detectable:** Phase 12; no read model exists.
14. **Read-model inconsistency is repairable:** Phase 12.
15. **Redis loss cannot invalidate authoritative state:** PostgreSQL is the only
    current store; Redis integration/failure behavior is deferred.

The dedicated concurrency group commits data and checks real independent PostgreSQL
sessions. The ordinary suite keeps transactional wrappers. Removing locks must fail
the concurrency suite; actual mutation/repetition results are recorded in progress.md.
Normal accepted sequences are contiguous while history is immutable, but the public
contract promises monotonicity, not gaplessness after privileged changes.


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
| ends_at >= original_ends_at, original end is non-null | SQL CHECK/NOT NULL and frozen terms | integration/deadline_constraints_spec.rb; models/soft_close_spec.rb |
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
| One retained actor/operation/key identifies one semantic command | Composite SQL unique index on actor_id,operation,key_digest; canonical SHA-256 fingerprint | integration/idempotency_constraints_spec.rb; requests/idempotency_spec.rb |
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
record exists, assume cryptographic digest collision resistance, and do not create
an authentication boundary. Processing rows are normally uncommitted; direct SQL
can violate that workflow despite structural checks. No arbitrary 500 is cached.
