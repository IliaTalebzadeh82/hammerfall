# Hammerfall: 10–15 minute technical walkthrough

Use this as a spoken route through the [case study](case-study.md), then open its targeted evidence links for questions. The timings are cues, not a directory tour.

## 0:00–1:00 — opening (about 60 seconds)

“Hammerfall is an auction engineering case study about one authoritative outcome under contention and failure. A bid is harder than an ordinary write: current price, private maximum, reserve, deadline and eventual winner interact. PostgreSQL holds the auction truth; Rails decides commands under a per-auction row lock and a database clock. Kafka, Redis and browser updates distribute a committed result. I focused on three failure stories: last-second competing bids, a committed bid whose HTTP response disappeared, and point-in-time recovery where Kafka and Redis still remembered a discarded future. Those were exercised with independent database sessions, real local replicas and transport, and an isolated recovery drill. It is a bounded reference architecture, not a Catawiki clone or production capacity claim.”

## 1:00–3:00 — one authority, several observers

Show the [primary diagram](case-study.md#architecture-in-one-picture). Follow one authenticated bid and its immutable client key to Rails, then the PostgreSQL idempotency claim and auction lock. Price, leader, accepted history, deadline and outbox intent share the commit. Follow the outbox later to Sidekiq/Action Cable revision hints and Kafka audit/Redis projection. A hint is followed by a fresh GET. Ask what would happen if a publisher crashes after Kafka delivery but before recording its acknowledgment: delivery can repeat, so consumers need receipts/revision rules. [Consistency model](consistency-model.md).

## 3:00–6:00 — concurrent present

Set up two bidders seeing the same price near deadline. Reading then writing in separate transactions would allow stale acceptance. Show [the concurrency test names](../apps/api/spec/integration/concurrent_bidding_spec.rb) or [ADR-003](adr/003-auction-concurrency-control.md): one locks, the other waits and rechecks. The database time is sampled after that wait. Proxy responses and one extension settle inside the same transaction; a closer either rechecks after an extension or closes first and causes the waiting bid to reject. Refer to the [combined €650/rapid example](marketplace/phase-21-final.md#combined-scenario-and-failure-behavior). State the cost: the hot row and waiting connections serialize that auction.

## 6:00–8:00 — ambiguous past

A client receives no response after commit. It retains the same key, actor and payload. A retry through another replica finds the stored terminal outcome and does not perform another bid or deadline extension; a fresh GET then establishes current public state. Show [ADR-006](adr/006-client-command-idempotency.md) and [lost-response test](../apps/api/spec/requests/idempotency_spec.rb). The record's retention and keyring become operational obligations.

## 8:00–11:00 — recovered history

Draw the timeline: PostgreSQL/Kafka/Redis at revision 5, then PostgreSQL restored to 4. A correct Redis monotonic-revision check refuses a lower seed; old Kafka can later restore discarded 5. The [Phase 22 drill](operations/phase-22-final.md#integrated-local-game-day) fenced traffic, quarantined old Kafka, cleared/reseeded Redis at 4, republished retained outbox events 1–4 to fresh Kafka, deduplicated audit receipts and regenerated Sidekiq work. T2's retained key replayed; T3's acknowledged success was outside the recovery point. State the nonzero data-loss boundary and procedural fencing dependency.

## 11:00–13:00 — evidence and limits

Use the [evidence table](case-study.md#supporting-propagation-and-failure-evidence). The 600-contender local burst completed with 1 valid acceptance and 599 expected rejections; the 1,000-attempt run degraded at a process FD limit. The [Phase 15 profile](benchmarks/phase-15-final.md#causal-model) found Puma admission pressure while measured lock waits were small. A passing checker establishes that run's final authoritative state, not production user capacity. No managed cloud recovery, multi-region behavior or production RPO/RTO was measured.

## 13:00–15:00 — discuss a changed workload

Ask which metric would justify a new boundary. If one auction is hot, inspect arrival mix, admission, lock and checkout before a per-auction sequencer or optimistic retry. If read/fanout dominates, measure replica lag and socket pressure separately. If organizational ownership or availability differs, evaluate service extraction with a deliberate authoritative data boundary. If recovery time matters, exercise representative restore volume and broker/secret-store timelines. Use the [interview guide](interview-guide.md#what-would-change-at-real-scale) to challenge these choices.

## Proposed short showcase for Session 2

Prepare one local Compose startup and one deterministic fixture command. Show two authenticated bidders: a hidden-reserve/stepped auction, A's private maximum, B's late competing maximum, the public leader/price/extended deadline and final winner. Optionally replay B's identical key through the other replica and inspect the current GET plus Kafka audit/Redis revision. Keep timing and output predictable. Session 2 must build, run and document the exact script; [Phase 21's existing combined smoke](../apps/api/script/phase21_final.rb) is a starting evidence path, not yet the polished demo. Explain PITR from retained reports rather than making it a ten-minute live step.
