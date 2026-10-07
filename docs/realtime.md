# Real-time auction updates — Phases 7–8

PostgreSQL owns auction truth. REST exposes current public state. Action Cable only
announces that the browser should check again. The runtime uses PostgreSQL
LISTEN/NOTIFY, so a job broadcast reaches a socket attached to another Rails
process. Redis now queues that job; it is not the Cable adapter. Test adapter
delivery alone is not evidence of cross-process behavior.

## Revision and publication

`public_revision` is bigint, NOT NULL, default 0, CHECK >= 0. Existing records and
new drafts start at zero; creation emits no message because listings do not
subscribe. Under the existing auction row lock, one logical operation increments
once when public fields change:

- Changed draft terms, schedule, activate, cancel and authoritative closure.
- Accepted manual or maximum commands that change public price/leader/history.
- Soft-close extension, including a protection-only increase inside the final minute.
- A proxy contest generating multiple visible bids plus extension still increments once.

Private-only maximum creation/increase outside the extension window, identical
maxima, rejected/rolled-back commands, replay, pruning, unchanged edits and early or
duplicate closure do not increment or broadcast. Private-only changes also leave
public timestamps unchanged. Bid generation changes price or leader under current
resolver rules; bid sequence alone cannot represent lifecycle/extension changes.

The explicit domain save helper writes state, revision and the public outbox row
inside one PostgreSQL transaction. An independent publisher later enqueues
`AuctionChangedJob` using scalar ID/revision. Nested savepoint or outer rollback
removes both state and row. No per-Bid model callback publishes incomplete
contest state.

```text
Rails A                     PostgreSQL                Rails B               Browser
lock + public mutation ---> row state + revision + outbox intent
COMMIT -------------------> authoritative/visible + pending intent
independent publisher ----> Redis queue -> Sidekiq job reads current revision
                                          -> NOTIFY -> public stream ------> hint
                                                                         GET REST
                            current state <---------- Rails HTTP <----------|
```

The application payload is exactly:

```json
{"type":"auction.changed.v1","auction_id":42,"revision":17}
```

Cable protocol welcome/ping/confirmation frames are separate transport messages.
No maximum, priority, origin, actor identity, command payload/result, idempotency
key, price or winner is sent in an invalidation. Public AuctionChannel validates
positive existing bigint IDs and rejects malformed/unknown subscriptions. There
are no actor/private channels. Origin checks are exact and intentional; see
[running locally](running-locally.md) for development and production configuration.

## Browser recovery and ordering

The detail page first GETs auction/history, then subscribes. Every subscription
confirmation, including reconnection, queues another GET. This closes the window
where a commit happens between the initial read and subscription establishment.

```text
initial GET revision 12
       | commit 13 (no subscriber yet)
subscribe -> confirmation -> GET revision 13 -> render authoritative state
socket lost -> commit 14 missed -> reconnect/confirm -> GET revision 14
```

Only higher revision hints trigger refresh. One read pair can be active; bursts
retain the highest target instead of starting concurrent fetches. A forced refresh
queues behind an active read. An unchanged unmet hint gets at most one follow-up;
new hints/forced recovery can queue further serial reads. REST responses older than
the displayed revision are rejected. Equal REST revisions may refresh history.
Read failures retain current state and offer explicit recovery. GETs have a timeout.
There is no periodic polling loop. Disposal aborts reads and disconnects the owned
consumer, preventing route/unmount callbacks and reconnect leaks.

```text
known revision 20 <- ignore hints 20, 19
hint 21 -> GET in flight; hints 22,23,24 -> remember 24
GET returns 22 -> accept, follow up -> GET returns 25 -> accept
later hint 24 -> ignore
```

Command responses retain their independent meaning. A terminal response resolves
its saved intention and requests fresh REST. An event before/after that response
cannot supply acceptance or erase an ambiguous attempt. Historical idempotency
replay still resolves the original operation, followed by current-state reads.
The connection indicator never disables valid bid controls or implies REST health.
REST failures remain independently visible. Listings use explicit REST pagination.

## Failure and operational limits

Commit can succeed and the process can die before enqueue; the outbox row remains
for another publisher. Enqueue failures persist retry state without undoing a
committed command or idempotency record. Redis/worker failure can delay a hint;
Sidekiq retries failed jobs five times and then retains them in its Dead set.
The job reads current PostgreSQL revision so delayed/reordered work does not
broadcast an older revision. Duplicate hints are harmless to the browser.
PostgreSQL NOTIFY and Cable do not retain missed events.
A continuously connected browser may remain stale after a lost hint until manual,
visibility, command, countdown, later-hint or reconnection recovery. Kafka
domain events and Redis projection repair do not guarantee Cable hint delivery,
and there is no exactly-once transport claim.
Successful outbox acknowledgment proves enqueue only. Redis loss afterward,
exhausted job retries or Cable failure may still lose a hint.
Auction and history GETs can straddle commits; this is not an atomic snapshot.

Each listening Rails process uses a dedicated PostgreSQL connection in addition to
its ordinary pool. Default two Cable workers and three pooled connections are local
bounded defaults, not capacity guarantees. Hot-auction fanout causes REST read
amplification. Review database limits, pool contention, proxy timeouts, WSS/origins,
authentication and rate limits before production. Phase 20 added session-backed
identity and bounded Cable admission; production ingress remains unverified.

Migration downgrade refuses nonzero revisions. Dropping/restarting an active revision
namespace would invalidate connected-client ordering; preserve metadata and stop
clients before any planned downgrade. Direct privileged SQL can bypass application
workflow guards and must not be used for ordinary domain changes.

## Verification

Committed PostgreSQL specs prove outermost-commit visibility, savepoint and outer
rollback, one contest revision, private-only silence, replay/no-op silence, duplicate
closers and post-commit enqueue/broadcast failure isolation. Phase 8 job specs
cover stale/duplicate hints, privacy, bounded sweep pagination and read-only drift.
Channel specs cover invalid
IDs and stream boundaries. Coordinator, subscription and component tests exercise
ordering, coalescing, cleanup, reconnect, REST failure and ambiguous-command overlap.

`apps/web/scripts/verify-realtime.mjs` requires two HTTP origins and proves A-to-B
publication over real sockets plus origin/subscription isolation. Playwright's two
clients prove manual/proxy settlement, deadline extension, winner closure and missed
commit recovery. See [progress](progress.md) for actual runs and sabotage results;
[ADR-008](adr/008-realtime-auction-invalidations.md) records alternatives.
