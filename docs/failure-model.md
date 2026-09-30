# Failure model

## Current foundation

| Failure | Current effect | Recovery |
| --- | --- | --- |
| PostgreSQL unavailable | Database operations/tests fail; `/up` may still return 200 | Restore PostgreSQL, then retry startup/database checks |
| Rails unavailable | `/up` fails; static frontend can still load | Restart API and inspect logs |
| Next.js unavailable | Starting page unavailable | Restart frontend and inspect logs |
| Dependency registry unavailable | First install/build or startup install can fail | Restore registry access and retry; lockfiles remain authoritative |

Historically, Phase 3 persisted serialized manual/proxy bidding. Private maximum/priority updates,
all visible bids, current price and leader commit together or roll back. If a response is lost after commit, clients cannot
safely deduplicate a retry yet. Application restart does not erase PostgreSQL data;
a local volume is not a backup. Ended auctions need an explicit close action.
Existing bid/close commands share the auction row lock; distributed time and
closing workers remain future work. Lock waiters consume connections; unexpected
database errors propagate without broad retries. No failover or
availability promise is made. Later phases must document Redis/Kafka outages, worker/consumer
crashes, dropped WebSockets, publication delays, duplicate events, latency spikes,
and delayed/concurrent closing workers using the
[operations architecture](architecture/operations-and-security.md)'s questions:
what remains correct, unavailable or stale, and how recovery happens.

## Phase 7 transport failure

Broadcast failure after commit is logged without undoing acceptance or idempotency
completion. Commit-before-process-crash can lose a notification. Disconnect/reconnect
recovers by current REST state, not message replay. REST errors are shown separately
from Cable connection status; a pending ambiguous command remains pending even when
new revisions arrive. A stale connected client needs a later hint, visibility/manual
refresh or reconnection. No durable delivery or periodic reconciliation is claimed.

## Phase 8 Redis and Sidekiq failure (historical)

After the outermost auction commit, an API callback enqueues a public
`AuctionChangedJob`. Redis outage or enqueue error is logged without undoing the
bid, deadline, winner, public revision or idempotency outcome. The API can boot
without Redis. The worker can be stopped while Redis queues hints; restart drains
the backlog. Duplicate/reordered work broadcasts current PostgreSQL revision and
the browser ignores equal/stale hints. A job error retries five times and then
enters the Dead set. Redis data loss, failed enqueue and a crash between commit
and enqueue can lose a hint permanently; REST recovery remains necessary.

The independent scheduler enqueues read-only PostgreSQL consistency sweeps. Its
Redis outage delays diagnostics, never auction authority. One-shot failure exits
nonzero; duplicate scheduled sweeps are harmless. A sweep detects price/latest
Bid or leader/winner mismatch, logs public auction ID and does not repair. There
is no Redis projection or outbox. See [ADR-009](adr/009-sidekiq-public-notifications-and-sweeps.md)
and the [runbook](runbooks/sidekiq-redis.md).

## Phase 9 transactional outbox

The public auction revision and outbox row commit in one PostgreSQL transaction.
Rollback leaves neither. The old commit-to-enqueue crash window is closed: an
API crash after commit leaves a pending row that another publisher discovers.
Redis outage does not roll back a bid or idempotency outcome; enqueue failure
persists a retry time and error class. Redis restoration lets the publisher drain
the due backlog. A publisher crash before enqueue leaves the row pending; a
crash after enqueue but before PostgreSQL acknowledgment may enqueue twice.
`SKIP LOCKED` allows separate publishers to advance different rows without a
global lock, but does not guarantee delivery order, including within an auction.

Successful Sidekiq enqueue marks `published_at`; it does **not** prove worker
completion, Cable broadcast or browser receipt. Redis data loss after that mark,
Sidekiq Dead-set exhaustion or broadcast failure can still lose a hint. A
connected browser can remain stale until a REST recovery trigger. The current
job reads PostgreSQL revision and tolerates duplicate/out-of-order hints.
Repeated publisher errors remain visible as pending rows and aggregate backlog,
retry and age logs; operators must investigate poison rows. No finite recovery
deadline or exactly-once delivery is promised. See [ADR-010](adr/010-transactional-public-outbox.md).

## Phase 10 Kafka failure

Kafka is downstream of the same committed public outbox row. Broker outage
leaves `kafka_published_at` empty with persisted attempts/backoff; auction
acceptance, idempotent outcome, closing and the independent Redis/Sidekiq/Cable
path continue. Broker recovery drains due rows. A delivery report can precede
a publisher crash; the PostgreSQL acknowledgment then rolls back and a retry
can produce the same event ID twice. `kafka_published_at` means broker delivery
was confirmed, not consumer completion or retention beyond broker policy.
Concurrent publishers may reorder an auction's revisions.

The audit consumer writes a PostgreSQL receipt and audit entry atomically, then
stores and synchronously commits its Kafka offset. Crash after the effect but
before offset commit replays a duplicate no-op. A database failure leaves the
offset uncommitted. Unknown version, malformed, oversized or conflicting
event ID is poison: the consumer logs partition/offset/error class and exits
without committing. Later records in that partition wait. Operators inspect
and explicitly reset/skip only after review, then restart. Replay from retained
offsets is idempotent but blocks again on the same poison. See the [Kafka runbook](runbooks/kafka.md)
and [Phase 10 ExecPlan](plans/phase-10-execplan.md) for live evidence.

## Phase 11 Redis projection failure

The projection group writes a public-only Redis snapshot after Kafka delivery,
then commits its own offset. A duplicate or stale event is harmless; an equal
revision with different public data, invalid event, Redis error or corrupt key
stops progress with the offset uncommitted. A crash after a successful Redis
write but before offset commit replays an equal-data duplicate. None of these
paths modifies PostgreSQL auction state or command outcomes.

Redis outage leaves bids, closing, ordinary GET and PostgreSQL outbox intact.
The explicit eventual GET falls back to PostgreSQL on miss, corruption or
connection failure and labels its source. A well-formed stale key remains a
stale Redis response, so callers requiring current state use ordinary GET.
After total Redis loss, previously committed Kafka offsets do not replay
automatically; operators seed current auction state with
`bin/rebuild_auction_projections`. Finite Kafka retention, historical rows and
poison records make Kafka-only reconstruction unreliable. A corrupt key must
be removed before replay/seed can write it. See [ADR-012](adr/012-redis-public-projection.md)
and the [recovery runbook](runbooks/redis-projection.md).
