# Phase 16 — final chaos review

Status: final local verification passed; hosted CI is the closure gate. Phase 17
has not started. Evidence: [Session 1](session-1.md), [Session 2](session-2.md),
and [final gates](final-gates.md). All faults used one local Compose API instance,
PostgreSQL, Redis and a single-node Kafka broker. No observed duration is an SLA.

## Correctness model

PostgreSQL owns auction state, bid history, private maximums, command identity
and outcomes, public revision, and immutable outbox intent. The outbox feeds
Kafka audit and Redis projection consumers, and separately feeds Sidekiq
realtime jobs. Cable carries only `{type, auction_id, revision}` invalidation
hints. REST reads PostgreSQL for current public state; an eventual read may use
Redis or fall back to PostgreSQL. Kafka, Redis, Sidekiq and Cable may lag,
duplicate, disappear or restart without deciding bid legality, price, deadline
or winner. Separate auction and history GETs are not one database snapshot.

**Delivery is at least once, not exactly once.** Session 2 observed Kafka accept
an event, the publisher die before SQL acknowledgment, then the same event ID
arrive again after restart. Both consumers logged `duplicate`. The transactional
outbox closes the database/publication-intent gap but cannot make broker
delivery exactly once. Stable event identity and consumer deduplication made
the durable audit effect occur once for that event; Redis's revision guard kept
the public projection from regressing. The audit DB transaction and Kafka offset
are also separate: a post-effect crash left the offset behind, redelivery was
deduplicated, and the offset later advanced.

## Failure observations and recovery

| Failure injected | Authority safe? | Recovery observed | Expected degradation / action |
| --- | --- | --- | --- |
| Redis stopped; fixture projection key removed | Yes | Eventual GET fell back; targeted reconciliation repaired the lost key after restoration | Derived read or Sidekiq lag. Restore Redis; reconcile if a key remains missing or stale. |
| Kafka broker stopped | Yes | Pending outbox rows drained, audit and projection converged after restoration | Kafka/audit/projection lag. Restore broker. |
| Sidekiq and notification publisher stopped | Yes | Pending enqueue rows drained after restart | Browser may miss hints. Restore workers; client REST refresh recovers truth. |
| Kafka publisher killed with pending rows | Yes | Same outbox event IDs survived and backlog drained after restart | Publication lag. Restart publisher. |
| Publisher killed after broker acceptance, before SQL ack | Yes | SQL row stayed pending; restart caused observed duplicate broker delivery, with one audit effect | At-least-once delivery; no manual event rewrite. |
| Audit consumer killed after DB effect, before offset commit | Yes | Receipt/effect stayed 1/1; offset stayed behind, duplicate redelivered, offset advanced | Temporary rebalance lag. Restart consumer. |
| API restarted | Yes | PostgreSQL state, maximum priority and completed outcomes persisted | Temporary request outage. Restart API. |
| HTTP response lost after command commit | Yes | Same-key/same-payload retry returned historical 201 and original bid ID; no new mutation | Client outcome ambiguous until retry; then GET current state. |
| API died before command commit | Yes | SQL rollback left no partial bid, revision, outbox or completed record; same-key retry executed once | Lost connection; client retries its original intention. |
| API alone unavailable | Yes | Independent publishers/consumers drained outboxes and Redis converged while API was exited | REST and new commands unavailable until API returns. |

Session 1's live duplicate replay and Session 2's publisher retry both produced
actual duplicate broker deliveries, with no duplicate durable audit effect or
stale Redis overwrite. Direct PostgreSQL checkers passed every retained
campaign. The invalid harness attempts in both session reports are excluded
from those conclusions. Phase 12 lease/fencing/restart tests, Session 1's
targeted Redis repair and Session 2's API-only derived processing form the
reconciliation evidence chain; Phase 16 did not repeat the Phase 12 campaign.
After a dependency or worker was restored, pending publication and consumer
processing converged without rewriting auction state. A deliberately stopped
service still needed restoration; an ambiguous HTTP response needed a client
same-key retry; a missed browser hint needed a REST recovery trigger. Corrupt,
ahead or equal-conflicting Redis keys remain operator-review cases.

## Browser and process boundary

The normal real-Chrome scenario observed a Cable revision hint prompt a REST
refresh, then blocked a WebSocket message: the second client remained stale
until subscription confirmation triggered REST, without event replay. The
opt-in worker-outage scenario stopped **both** the independent Sidekiq and
Sidekiq outbox publisher processes while the API/Cable socket stayed up. A
bid committed at revision 3; no hint reached the observer; its displayed
history remained empty while ordinary REST reported the new price and leader.
Explicit browser refresh fetched that bid. After worker restoration, a later
bid advanced revision 4; its Cable hint led to REST refresh and the browser
matched the authoritative price, leader and two-row history. The browser did
not apply a price from the hint, display a private maximum, or submit a
duplicate mutation. This proves the existing explicit and later-hint paths;
it does **not** promise automatic refresh during a silent hint loss while a
page remains open. Visibility refresh and subscription confirmation are other
existing REST recovery paths.

Compose owns these roles separately: `api` serves Rails HTTP and Action Cable;
`sidekiq` executes notification jobs; `outbox-publisher` enqueues those jobs;
`kafka-outbox-publisher` publishes to Kafka; two Kafka consumers handle audit
and Redis projection; `reconciliation-scheduler` enqueues scans; and
`auction-closer` finalizes due auctions. Stopping Sidekiq alone does not stop
Action Cable, and stopping the API does not stop already-running publishers.

## Failure-timing taxonomy

| Window | Recovery mechanism demonstrated |
| --- | --- |
| Before authoritative commit | PostgreSQL rolls back the domain work, outcome and outbox together; same-key retry executes once. |
| After authoritative commit, before client acknowledgment | Completed idempotency outcome replays for the same key and payload; a fresh GET supplies current state. |
| Before external delivery | Committed outbox intent stays pending through Redis/Kafka/worker or publisher outage, then retries. |
| After external delivery, before local acknowledgment | Outbox row can retry the same immutable event; downstream event-ID/revision guards suppress duplicate durable effects. |
| Before consumer durable effect | Uncommitted Kafka offset causes redelivery; consumer attempts the effect again. |
| After consumer durable effect, before transport acknowledgment | Redelivery encounters the committed receipt/effect and advances offset without a second effect. |

Expected degradation includes stale derived reads, PostgreSQL fallback,
pending outbox, Kafka lag, missed realtime hints, connection loss, API outage
and rebalance delay. A missing accepted PostgreSQL bid, duplicate bid mutation,
duplicate audit effect, stale Redis overwrite, false outbox acknowledgment,
re-executed completed replay or partial committed transaction would be a
correctness failure. None was observed in retained passing campaigns.

## Safety and limits

Crash hooks require development/test Rails, an exact local confirmation token,
an exact boundary and a matching event/auction ID. Atomic container-local
markers make each configured fault one shot across process respawn. Base
Compose defines no chaos variables; a fresh recreation contains no old marker
or fault override. The hooks do not change event identity or payload. Production
environment guards make them inert even if opt-in variables are supplied.

The evidence is local, single API instance, one Kafka broker, and a shared
Redis service that also stores Sidekiq data. It does not cover multi-instance
races, Kubernetes or cloud behavior, network partitions between replicas,
regional failures, PostgreSQL primary failover, full Redis volume destruction,
Kafka durability beyond this configuration, or production recovery times.
Short Prometheus scrapes missed some transient backlogs, so direct SQL rather
than telemetry was used for correctness. A valid stale projection may await
scheduled reconciliation; equal-conflicting, corrupt or ahead keys still need
operator review under the existing runbook. A lost browser hint can leave an
open page stale until an explicit refresh, visibility change, reconnection or
later hint. No Phase 17 horizontal deployment guarantee follows from Phase 16.
