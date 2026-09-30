# Current handoff — Phase 10 complete

Updated: 2026-09-30. **Phase 10 — Kafka is complete.** Phase 11 has not begun
and needs an explicit request. Read [ADR-011](../adr/011-kafka-domain-events.md),
the [Phase 10 ExecPlan](../plans/phase-10-execplan.md) and [progress](../progress.md)
for the contract, Evidence Index, actual failure results and limits. The
implementation is commit `874deb7`; documentation completion follows.

## Current state

- Rails/PostgreSQL remains auction, deadline, proxy, winner, public revision
  and idempotency authority. A public mutation, revision, Sidekiq invalidation
  intent and public Kafka domain snapshot commit on one outbox row inside the
  auction transaction. Legacy Phase 9 rows were not backfilled with invented
  domain history. No Redis auction projection or Phase 11 consumer exists.
- Sidekiq/Cable and Kafka have separate publishers, retries and acknowledgment
  fields. The Kafka publisher sends committed rows to the three-partition
  `hammerfall.auction-events.v1` topic with auction ID key using `rdkafka`
  0.30.0, waits for broker delivery, then acknowledges in PostgreSQL. The
  `hammerfall.audit.v1` group validates v1 public envelopes, commits receipt
  and audit effect together, then commits offset. Duplicates and replay are
  no-ops; poison stops the group at an uncommitted offset.
- Redis/Sidekiq/Cable still send public revision hints; browser REST remains
  the current-state authority. Kafka audit is not a projection and never
  decides bids, price, deadline or winner. [Kafka runbook](../runbooks/kafka.md)
  covers backlog, replay, poison and operator recovery.

## Evidence and limits

Real broker outage left a bid committed and Sidekiq hint acknowledged while
Kafka backlog persisted; recovery drained it. Publisher SIGKILL after broker
delivery produced two records/one audit effect. Consumer SIGKILL after its
database effect replayed as a duplicate on restart. A version-2 poison record
blocked its partition; an explicitly reviewed offset reset resumed a later
valid record. Replay suppressed old effects and blocked at the same poison.
Redis outage left Kafka and audit 3/3 while Sidekiq waited; Redis recovery
drained that backlog. Sabotage A–D failed expected checks, then 19 focused
examples passed after byte-identical restoration. Final review added
event-classification and a two-connection duplicate-consumer race check;
22 focused examples passed.

Final local `scripts/check` passed 381 RSpec examples, 98 Ruby lint files,
Brakeman, Zeitwerk, 73 frontend tests and production build. Compose started
the Kafka topology; native host bootstrap worked. Real Playwright passed 7/7;
API, proxy, concurrent, two-process idempotency and multi-process closing
smoke passed. Bundler audit found no vulnerabilities. Hosted CI was not run.

Kafka is one local plaintext broker with one replica and no production HA,
backup, TLS/ACL, schema registry, alerting, capacity or fixed-latency evidence.
Retention bounds replay; poison skip needs an operator decision. Concurrent
publishers can reorder an auction's revisions, and the two publishers share
outbox row locks. Sidekiq acknowledgment still means queue enqueue, not Cable
or browser delivery. REST recovery remains necessary. Phase 11 is ready for
**separately requested design and implementation**, carrying these ordering,
retention and privacy limits forward; no Phase 11 work has started.
