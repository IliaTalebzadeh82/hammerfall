# Engineering conversation guide

Use a short answer, then evidence and the condition that would change the choice. The [case study](case-study.md) is the narrative; this is a defense and discussion aid.

## Why PostgreSQL, rather than Kafka, decides the auction

**Short answer:** the command must synchronously decide legality from price, private maxima, reserve and deadline, and atomically record its result. PostgreSQL gives this project one transaction and one ordering domain. Kafka carries public committed snapshots after that decision.

**Deeper/trade-off:** A Kafka command log with a per-auction single writer could be valid, but would require durable partition ownership, replay/duplicate semantics, low-latency reply handling, failover and carefully defined read freshness. The present outbox closes the commit-to-publication loss window while allowing duplicate delivery. Kafka can be unavailable while bidding commits, but downstream views lag. [ADR-010](adr/010-transactional-public-outbox.md), [ADR-011](adr/011-kafka-domain-events.md). Revisit if measured command volume or ownership requirements make the PostgreSQL critical section and admission unacceptable.

## Why a pessimistic auction row lock?

**Short answer:** after one lock, every writer and the closer validate the same fresh auction state and database time. It is easy to audit across Rails replicas.

**Deeper/trade-off:** Optimistic version/CAS needs full rollback and retry of bids, proxy rows, priority and extension; repeated collisions cost work. A distributed lock adds a second authority/failure mode unless the database still enforces fencing. A single-writer actor or partitioned command processor can reduce database contention but needs durable takeover semantics. The lock serializes a hot auction and waiting connections consume capacity. [ADR-003](adr/003-auction-concurrency-control.md), [independent-session specs](../apps/api/spec/integration/concurrent_bidding_spec.rb). Revisit on measured per-auction arrival/latency, not total marketplace traffic alone.

## What if 10,000 people bid on one auction?

**Short answer:** Hammerfall has no evidence it can serve that burst. The auction row serializes decisions; Puma admission, sockets and DB connections can fail before lock time dominates.

**Deeper/trade-off:** The 600-contender local final-ten burst was clean; 1,000 attempts produced 28 server errors and 64 timeouts at a 1,024-FD soft limit. In a separate 64-VU profile, Puma backlog was high and measured lock/checkout waits were low relative to HTTP tail. [Burst evidence](benchmarks/phase-14-session-2.md#closing-storm-and-final-ten-second-challenge), [profile](benchmarks/phase-15-final.md#causal-model). Measure admission, queue wait, per-auction accepted work, client retry load and connection budget. Consider controlled admission, partitioned auction ownership or a sequencer only with equivalent winner/deadline/failover proof.

## Why isn't Kafka exactly once?

**Short answer:** a publisher can deliver then die before saving acknowledgment; a consumer can commit its effect then die before offset commit. Both paths replay.

**Deeper/trade-off:** The outbox retains intent; immutable event IDs and a PostgreSQL receipt make audit effects idempotent; Redis revisions reject stale projection events; reconciliation detects drift. Poison records and broker outages still need operations. The [Phase 22 replay](operations/phase-22-kafka-recovery.md#observed-sequence-and-evidence-index) observed three duplicate receipts and one new effect. Revisit partitioning, schema and consumer governance as consumers grow, without claiming transport exactly once.

## What if Redis or Kafka disappears?

**Redis:** PostgreSQL auction truth remains. The eventual endpoint has a PostgreSQL fallback; missing/older public projection can be rebuilt; ahead/conflicting/corrupt projection needs review. [ADR-012](adr/012-redis-public-projection.md), [reconciliation invariants](invariants.md#phase-12-reconciliation-invariants). Redis loss may reduce freshness or queue availability, not decide winner.

**Kafka:** committed bids and outbox snapshots remain in PostgreSQL; publication backs up and resumes later. Audit/projection lag, retention and operator intervention are real concerns. [Kafka failure invariant](invariants.md#phase-10-kafka-invariants). Revisit with measured lag, recovery windows and consumer needs.

## What if a response disappears after commit?

Retry the **same** actor/operation/key/payload; return the stored historical outcome, then GET current state. A changed payload conflicts, an expired but retained record still owns its key, and a physically pruned record can no longer protect replay. [ADR-006](adr/006-client-command-idempotency.md), [lost-response spec](../apps/api/spec/requests/idempotency_spec.rb). The client must preserve command identity; a Cable hint cannot prove the command result.

## What if maxima tie, or a bid races the closer?

Equal ceilings use durable earlier-maximum priority even if visible amounts match. [ADR-004](adr/004-proxy-bidding.md), [maximum competition tests](../apps/api/spec/integration/concurrent_maximum_bidding_spec.rb). If a qualifying bid locks first, it may extend and the closer rechecks. If the closer locks and finalizes first, the waiting bid rejects. Eligibility uses database time after lock, so arrival before the old deadline alone does not authorize a late waiter. [ADR-005](adr/005-auction-deadlines-and-soft-close.md), [Phase 21 race evidence](marketplace/phase-21-final.md#rapid-closing). No FIFO/fairness or exact close scheduler SLA is promised.

## What happens after PITR?

Restored PostgreSQL chooses the authoritative past. Quarantine ahead Kafka, clear/rebuild ahead Redis, replay retained outbox to a fresh broker, regenerate only retained Sidekiq work, reconcile and verify before releasing traffic. The local drill restored revision 4 from a world where other systems had seen revision 5; T3 was acknowledged but absent after restore. [Phase 22 report](operations/phase-22-final.md#integrated-local-game-day). The trade-off is operational complexity and nonzero RPO; a production design needs automatic or rigorously rehearsed fencing, managed-service DR and measured restore objectives.

## What would change at real scale?

| Current design | Observed limit or missing proof | Signal that justifies a change | Candidate and new complexity |
| --- | --- | --- | --- |
| Per-auction PostgreSQL row lock | Hot auction serializes; local test encountered Puma/FD pressure | Representative per-auction queue/decision latency remains unacceptable after admission tuning | Auction ownership partition, optimistic retry or sequencer; prove failover and one winner/order domain |
| Three-thread local Puma/pool | More threads moved wait to DB pool without repeatable gain | Production admission/checkout saturation under target workload | Bounded queues, pool/worker sizing; additional connections and overload policy |
| PostgreSQL-backed reads plus disposable Redis projection | Read replica and large fanout lag unmeasured | Read load or geographical latency threatens target freshness | Replica/read model with explicit staleness and failover contract |
| Outbox → Kafka → audit/projection | Local duplicate and PITR experiments only | Many consumers, high event volume or strict recovery windows | Schema registry/governance, retention, poison tooling, broker HA/DR and ownership |
| One modular Rails app | No demonstrated organizational scaling boundary | Distinct team ownership, deployment cadence, availability or data lifecycle | Bidding/catalog/realtime service split with explicit command authority and cross-service failure semantics |
| Single-region local authority model | No regional partition/failover proof | A real multi-region availability requirement | Chosen leader/quorum and clock/fencing model; latency and conflict costs |

These are options to test, not assertions about Catawiki's internal architecture. [Phase 15 measurements](benchmarks/phase-15-final.md) and [Phase 22 limits](operations/phase-22-final.md#final-adversarial-review) supply the current evidence boundary.

## Questions for Catawiki engineers

- Where has the boundary between synchronous bidding correctness and downstream processing been most useful?
- For unusually hot auctions, which pressure appears first in your measurements: admission, ordering, or client retry behavior?
- When an HTTP bid outcome is ambiguous, which product layer owns command identity and recovery messaging?
- Which bidding-policy changes have been hardest to roll out safely across active auctions and old events?
- How do you decide when an auction domain needs a separate deployment or ownership boundary?
- Which recovery exercises have most changed your assumptions about derived data after restoring authority?

These invite engineering discussion and do not ask for confidential implementation details.
