# Phase 16 Session 2 — ambiguous crash boundaries

2026-10-02. Starting SHA: `e45987e03c6b40f1612c406cb771435ee8e17276`.
One local Compose API instance, PostgreSQL, Redis and single-node Kafka. Each
retained campaign used an isolated auction. Polling was bounded to 120 seconds
(API health to 90 seconds), normally at five-second intervals. Durations below
are local observations, not availability promises. Direct PostgreSQL verification
and derived comparison closed each passing campaign. Session 1 campaigns were
not repeated.

## Evidence index

| Campaign | Raw evidence | Decision |
| --- | --- | --- |
| Publisher after broker acceptance, before SQL acknowledgment | [c0787859](p16-20261002T010633Z-c0787859/) | PASS |
| Audit consumer after DB effect, before Kafka offset | [6549301c](p16-20261002T010710Z-6549301c/) | PASS WITH EXPECTED DEGRADATION: group rebalance delayed redelivery |
| API restart, committed and uncommitted command ambiguity, API-only publication | [7f99f9b8](p16-20261002T011412Z-7f99f9b8/) | PASS WITH EXPECTED DEGRADATION: two client connections lost |
| API-only direct Redis/worker observation | [6948c6d6](p16-20261002T011754Z-6948c6d6/) | PASS WITH EXPECTED DEGRADATION: API unavailable while derived work continued |
| Replay-short-circuit sabotage | [failing test](sabotage-idempotency-replay.log), [restored test](session2-focused-tests.log) | PASS: expected failure, then restoration |

Invalid harness runs are retained: [c778cf8c](p16-20261002T010540Z-c778cf8c/)
tried `exec` into a stopped publisher; [4b0ea5e8](p16-20261002T010604Z-4b0ea5e8/)
used a one-off container that inherited a restart policy and later acknowledged
the row; [e3981716](p16-20261002T011203Z-e3981716/) used an asynchronous
signal from a Puma request and received HTTP 201, so response loss was not
established; [ea354f4c](p16-20261002T011718Z-ea354f4c/) compared Redis's
projection wrapper with the public data instead of its nested `data`. No
correctness failure was observed in those runs, and none is counted as proof of
the intended window. The harness was corrected and each relevant campaign rerun.

## Publisher: broker accepted, SQL ack absent

- **Scenario/precondition:** A converged active auction had one accepted bid and
  three public events. The normal Kafka publisher was stopped, then a second bid
  committed, leaving one fixture Kafka row pending.
- **Exact point/mechanism:** A one-off Rails publisher process received the
  broker delivery report and immediately died with exit 137 at the
  `kafka_delivered` hook, before `kafka_published_at` could be updated or its
  transaction committed. The hook is local/test only, event-ID scoped and
  opt-in. [Crash marker](p16-20261002T010633Z-c0787859/crash.log).
- **Expected ambiguity/degradation:** Kafka may contain the event while SQL
  still says pending; a restart can publish the same immutable event again.
- **Durable before/after:** The target event's public payload SHA-256 remained
  `e4d9c23c…99aaf9`; `kafka_attempts=0`, `kafka_published_at=NULL` and one
  pending row survived the crash. The first delivery produced one audit receipt
  and effect. The auction still had two bids and revision 4.
- **Recovery/retry:** Restarting the publisher delivered the same event ID
  again. Both [audit](p16-20261002T010633Z-c0787859/kafka-audit-consumer-duplicate.log)
  and [projection](p16-20261002T010633Z-c0787859/kafka-projection-consumer-duplicate.log)
  consumers explicitly logged `duplicate`. This is observed duplicate delivery,
  not merely a possible one. The row then had one SQL acknowledgment attempt;
  fixture backlog drained in 1.10 seconds after restart.
- **Final authority/effects:** Direct [checker](p16-20261002T010633Z-c0787859/verify.json)
  passed; target receipt/effect counts stayed 1/1, Redis public data matched
  PostgreSQL, the payload digest and outbox event ID were unchanged, and
  publication retry did not alter bid count, price or revision. [Before,
  crash and final snapshots](p16-20261002T010633Z-c0787859/).
- **Residual limit/decision:** Single-node local Kafka and one fixture event;
  no durability claim beyond its broker configuration. **PASS.**

## Audit consumer: DB effect committed, offset behind

- **Scenario/precondition:** The audit service was stopped after baseline
  convergence. A new bid's Kafka publication was acknowledged, but its audit
  receipt/effect count was zero.
- **Exact point/mechanism:** A non-restarting consumer process committed both
  `ConsumedKafkaEvent` and `KafkaAuditEntry`, then died with exit 137 at
  `audit_effect_committed`, before `store_offset`/`commit`. [Crash marker](p16-20261002T010710Z-6549301c/crash.log).
- **Expected ambiguity/degradation:** DB effect exists while the transport
  position is uncommitted; group restart must redeliver and deduplicate.
- **Durable before/after:** Target receipt/effect changed 0/0 to 1/1. For its
  partition, [committed offset](p16-20261002T010710Z-6549301c/offsets-before.txt)
  was 2274 with log end 2275 and remained 2274
  [after death](p16-20261002T010710Z-6549301c/offsets-after_crash.txt).
  Auction bid count stayed two.
- **Recovery/redelivery:** The normal consumer restarted, rebalanced and
  [logged `duplicate`](p16-20261002T010710Z-6549301c/kafka-audit-consumer-duplicate.log)
  for the same event ID. The [recovered offset](p16-20261002T010710Z-6549301c/offsets-recovered.txt)
  reached 2275; receipt/effect remained 1/1. The consumer resumed normal group
  work. Redelivery took roughly 45 seconds after restart because the killed
  group member first had to time out; the post-redelivery convergence poll took
  0.99 seconds.
- **Final authority/limit:** Direct [checker](p16-20261002T010710Z-6549301c/verify.json)
  and Redis comparison passed. This proves the audit group window; projection
  consumer crash was not repeated because Phase 11/12 and Session 1 already
  exercise equal/stale revision duplicate protection. **PASS WITH EXPECTED
  DEGRADATION.**

## API restart and ambiguous commands

- **Restart precondition:** An active auction had accepted bid history, price,
  leader, one private maximum and a completed idempotency outcome. Only the API
  container stopped. Direct PostgreSQL state while down and after restart had
  identical bid count, revision, outbox count, public fields, maximum count and
  completed command count. Adding a second equal ceiling after restart left the
  earlier maximum bidder in the lead and kept maximum priorities unique.
- **Committed/response lost:** A `place_bid` request used a new key scoped to
  the fixture. The `command_committed` hook synchronously exited the serving
  process after the idempotency transaction returned, before rendering. The
  client observed `RemoteDisconnected`. Direct SQL while the response was lost
  showed bids 4→5, revision/outbox 5→6, completed records 1→2. The API was
  recreated from base Compose configuration. A later bid changed state; the
  retry with the *same in-memory key and payload* returned HTTP 201 with
  `Idempotency-Replayed: true` and the original bid ID. The replay added no
  bid, revision, outbox row or record.
- **Uncommitted/response lost:** A second new-key bid died at
  `command_before_commit` after domain work but inside the open outer SQL
  transaction. The client again observed `RemoteDisconnected`. Direct SQL
  before/after was identical: six bids, revision/outbox seven, two maximum
  rows, two completed records. No partial bid, price/leader, priority count,
  public revision, outbox row or terminal outcome survived. After API
  recreation, the same-key retry returned a fresh HTTP 201 and created one
  completed outcome. The focused test also checks this rollback boundary.
- **API-only outage:** A committed bid with pending Kafka publication survived
  API stop; independently running publisher/consumer services drained it and
  audit reached the outbox count in 6.45 seconds. A separate targeted
  [outage snapshot](p16-20261002T011754Z-6948c6d6/during_api_outage.json)
  observed the API exited while both publishers, both Kafka consumers,
  Sidekiq and reconciliation scheduler were running. Kafka and Sidekiq outbox
  counts reached zero, audit effects reached four for four events, and Redis
  revision 4 plus all public fields matched direct PostgreSQL within 6.99
  seconds. API restart needed no reconstruction.
- **Final authority/decision:** [Main checker](p16-20261002T011412Z-7f99f9b8/verify.json)
  and [targeted outage checker](p16-20261002T011754Z-6948c6d6/verify.json)
  passed. The client connection losses and temporary API unavailability were
  expected. Sidekiq job execution and scheduler scan progress were not counted;
  only their process independence and outbox enqueue recovery were observed.
  **PASS WITH EXPECTED DEGRADATION.**

## Adversarial sabotage and safety boundaries

Temporarily inserted `yield` into the completed-record replay branch of
`Idempotency::Executor`, causing the existing lost-response/changed-state
request test to fail: it returned current `bid_too_low` instead of the original
201 body. The change was removed; the same test and focused boundary suite
passed. This demonstrates why the replay short-circuit is needed. No retained
live fixture or database schema was modified by the sabotage.

The crash hooks are disabled unless Rails is in development/test **and** the
exact confirmation token, boundary and event ID or auction ID are set. They
do not alter event identity or payload. One process death consumes the fault;
the API hook atomically claims a container-local marker so a respawned Puma
process cannot repeat the same fault. A [two-invocation live check](session2-hook-once.json)
exited 137 with the marker first, then exited 0 without a second marker.
Recreating the API from base Compose clears its temporary variables. They
never run in production. Focused tests cover inert defaults, production
guarding, correct boundary order and command rollback/replay; relevant suite:
46 examples, 0 failures, 1 pre-existing gated live-Kafka pending example.
RuboCop, Ruby syntax, Python compile and retained artifact privacy scan are
recorded in the [ExecPlan](../plans/phase-16-execplan.md).

## Causal conclusions and remaining work

Publisher death after broker acceptance **did** duplicate delivery with a stable
event ID. It did **not** duplicate audit effects or regress Redis. Consumer death
after its DB effect left the offset behind; redelivery was explicitly deduplicated
and advanced it. API restart did not lose auction truth or completed outcomes.
Both committed-but-unanswered and uncommitted commands were safe under same-key
retry, with different observed replay/fresh-execution results. These campaigns
recovered without operator action. Temporary API unavailability, lost responses,
pending rows and consumer rebalance were expected degradation.

No direct browser WebSocket subscription was observed in Session 2. Session 1
already proved the notification backlog while workers were stopped; a browser
REST recovery/Cable scenario belongs in the final browser session. Phase 12
lease/fencing tests plus Session 1 targeted repair sufficiently cover the
reconciler crash mechanism for this checkpoint; a repeated repair/cursor crash
campaign would add little without a new failure hypothesis. Full regression,
browser/runtime and hosted CI gates, final adversarial review and Phase 16
closure remain for a fresh context. No Phase 17 work began.
