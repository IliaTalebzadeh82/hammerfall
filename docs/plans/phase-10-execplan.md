# Phase 10 ExecPlan — Kafka

Status: COMPLETE — verified 2026-09-30. Phase 11 has not begun.
Current milestone: Phase boundary; await an explicit Phase 11 request.
Completed: Public snapshots and independent Kafka delivery state on the Phase 9 outbox; rdkafka publisher; strict v1 codec; transactional audit receipt/effect; single-node Compose broker/topic and dedicated roles; ADR-011 and Kafka runbook. Real outage, crash, replay, poison and sabotage campaigns completed.
Verified: 22 focused examples, 381 full backend examples, 98 Ruby files linted, zero Brakeman warnings, 73 frontend tests/build, 7/7 real browser tests, Compose and Kafka smoke, real failure/recovery, multi-process domain smokes and Bundler audit. Details below.
Remaining: None within Phase 10. Hosted CI and production capacity are unverified.
Known failures/limitations: No hosted CI, production capacity or broker HA proof. Single-node plaintext Kafka; no schema registry/alerting. Historical Phase 9 rows cannot be backfilled as domain events. The two publishers share row locks and can briefly delay one another. Poison requires operator review/reset. Phase 9 Cable loss limits remain.
Relevant files: `apps/api/app/models/{auction,outbox_event,consumed_kafka_event,kafka_audit_entry}.rb`, `app/services/kafka_*.rb`, two migrations, `docker-compose.yml`, `scripts/smoke-kafka`, Kafka specs.
Relevant ADRs: [ADR-010](../adr/010-transactional-public-outbox.md), [ADR-011](../adr/011-kafka-domain-events.md).
Next-session starting point: Phase 10 is complete. Start Phase 11 only on an explicit request, using the latest handoff, Phase 11 specification and this plan's ordering/retention/privacy limits.

## Primary implementation checkpoint

Completed implementation: outbox schema migration, public event classification/snapshot, Kafka publisher and consumer, Compose topology, targeted tests.
Completed verification: development/test migrations, Zeitwerk, focused 16 examples and changed-file RuboCop.
Failures found/fixed: focused test isolation initially counted setup lifecycle events; tests now explicitly acknowledge setup rows in producer cases. No implementation failure yet.
Remaining failure tests: real broker outage/recovery, producer crash after delivery, consumer crash/restart, poison, concurrency and sabotage.
Remaining regression: full backend/frontend/Compose/browser/security checks.
Remaining docs: ADR, event/failure/runbook/architecture, learning/code map/journal/progress/handoff.
Known limitations: No real Kafka result yet. Historical Phase 9 rows marked Kafka-acknowledged without invented domain meaning.
Next exact action: Build and start Compose, then run a real event through publisher and consumer.

## Live failure and integration checkpoint

Completed implementation: V1 public snapshots, publisher, audit consumer, receipt digest, Compose broker/topic, CI smoke and runbook.
Completed verification: Broker outage/recovery; Redis outage with Kafka continuing; real publisher and consumer SIGKILL windows; poison, operator skip and replay; sabotage A–D; full local regression, Compose and browser; multi-process idempotency/closing. A later two-connection consumer race test proved duplicate receipts serialize and the loser returns a no-op.
Failures found/fixed: First focused privacy assertion matched `origin` inside `original_ends_at`, changed to exact field-key check. Setup lifecycle rows were isolated in producer specs. A prior Compose consumer container retained `restart: on-failure` after YAML changed during startup; it was stopped and recreated with `restart: no`, then poison/replay behavior passed. A native Kafka probe initially lacked the new variable in the existing local `.env`; explicit host bootstrap succeeded. No unresolved serious implementation failure.
Remaining failure tests: None within Phase 10 scope.
Remaining regression: None; broad gate and browser passed after final code changes.
Remaining docs: Progress/handoff and final link/adversarial review.
Known limitations: Single broker, no backup/HA/TLS/ACL, no production latency/throughput evidence, operator poison skip, shared outbox row lock, legacy rows skipped for Kafka.
Next exact action: Complete documentation/adversarial review and commit.

## Decisions

- Keep PostgreSQL mutation, revision and outbox intent in one commit. Kafka is only an asynchronous reader of committed intent; broker failure cannot reject or change an auction command.
- Preserve the existing Sidekiq/Cable publisher and its acknowledgment. Add independent Kafka delivery acknowledgment to the same committed outbox row, avoiding a post-commit direct producer.
- Use public-only versioned domain event envelopes. Legacy pre-Phase-10 rows need an explicit migration policy; no fabricated historical domain semantics.
- Consumer side effects and a unique event receipt will share one PostgreSQL transaction. Kafka offset commit follows database commit; replay must be harmless. Poison records stop the affected consumer instead of being silently skipped.

## Failure and verification boundaries exercised

1. Schema/privacy and mutation atomicity: rollback, replay, private-only/no-op, version rejection, public revision mapping.
2. Producer: delivery confirmation before PostgreSQL Kafka acknowledgment; broker outage/backoff, crash between broker delivery and acknowledgment, concurrent claims, duplicate/reordering.
3. Consumer: real topic/group/partitions, receipt plus side effect atomicity, offset commit after effect, crash before offset, restart/replay, duplicate/stale events, poison record blocking and recovery.
4. End-to-end: Kafka off/on while bidding and Sidekiq/Cable continue; Redis and Kafka independently unavailable; no Kafka role in authority.
5. Sabotage: remove atomic event intent, acknowledge before delivery, disable receipt, commit offset before effect or accept poison; verify targeted checks detect each and restore source.
6. Completion: one final broad backend/frontend/lint/security/build gate, Compose startup, relevant browser/runtime smoke, documentation and adversarial review.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Phase 9 boundary inspection | Targeted auction/outbox model, publisher, migration and specs before implementation | Confirmed existing atomic public intent and separate Sidekiq enqueue ack | ADR-010; source paths above |
| Kafka client/infrastructure source review | Official rdkafka README and Apache Kafka Docker documentation | `rdkafka` producer delivery handles and consumer groups; official Apache image available | https://github.com/karafka/rdkafka-ruby ; https://kafka.apache.org/41/getting-started/docker/ |
| Schema and autoload | `bin/rails db:migrate` (development/test), `bin/rails zeitwerk:check` | Both migrations and autoload passed | Migration `20260930000001/2`; `/tmp/phase10-check.log` |
| Focused Phase 10 checks | `bundle exec rspec spec/integration/kafka_outbox_spec.rb spec/integration/transactional_outbox_spec.rb` after final review | 22 examples, 0 failures; seed 28907 | `/tmp/phase10-focused-complete.log` |
| Changed Ruby lint | `bundle exec rubocop` on 9 changed Ruby files | 9 files, 0 offenses | `/tmp/phase10-rubocop-focused.log` |
| Compose topology and end-to-end | `docker compose up --build --wait --wait-timeout 300`; `docker compose exec -T api ruby < scripts/smoke-kafka`; topic describe | All 11 running services healthy plus topic init complete; auction 197 revision 3, 3 Kafka acks and receipts; 3 partitions/replica 1 | `/tmp/phase10-compose.log`, `/tmp/phase10-smoke-kafka.log` |
| Kafka outage/recovery | Stop broker, bid on auction 196; inspect PostgreSQL/Sidekiq/Kafka; restart broker | Revision 4/price 11,000 committed, Sidekiq ack true, Kafka ack false/attempts 3/error `Rdkafka::RdkafkaError`; recovered ack at attempts 5, audit revision 4 | `/tmp/phase10-kafka-outage.log`, `/tmp/phase10-kafka-recovery.log` |
| Publisher crash after delivery | Stop background publisher; bid rev 5; one-shot publisher SIGKILL immediately before `kafka_published_at`; restart | Exit 137; Kafka audit observed first delivery while DB ack nil/attempts 0; retry acked; topic had 2 records with same ID `f4d54e73…`; one receipt/audit, revision stayed 5 | `/tmp/phase10-publisher-crash.log`, `/tmp/phase10-publisher-topic.log` |
| Consumer crash/restart | Stop group; bid rev 6; SIGKILL in `store_offset` after effect; restart | Exit 137; receipt/audit 1 before offset; restart logged `result=duplicate` at offset 6 and group caught up to offset 7; price remained 13,000 | `/tmp/phase10-consumer-crash.log` |
| Poison and replay | Publish schema-v2 record at partition 1 offset 7, bid rev 7 at offset 8; stop/recreate consumer, reset offset to 8; later reset to 0 and replay | Consumer exited 1, no poison receipt/offset; valid bid 14,000 and both publisher acks continued, audit waited; explicit reset processed rev 7; replay produced duplicate no-ops and stopped again at poison; restored offset 8 | `/tmp/phase10-poison.log`, `/tmp/phase10-replay.log` |
| Redis independence | Stop Redis, create auction 224/rev 3, inspect, restore Redis | Kafka ack/audit 3/3 with Sidekiq ack 0/3 while Redis down; later both 3/3 after recovery, price unchanged | `/tmp/phase10-redis-independence.log` |
| Sabotage A–D | Temporary remove outbox intent; remove producer `.wait`; disable receipt lookup; store offset before DB effect; focused spec per mutation, then byte-identical restore and rerun | All four mutants failed expected assertions; restored files `cmp` matched; 19 focused examples green | `/tmp/phase10-sabotage-{a,b,c,d}.log`, `/tmp/phase10-post-sabotage.log` |
| Full regression | `scripts/check` after final consumer-race and event-classification specs | 381 RSpec examples/0 failures; RuboCop 98 files/0 offenses; Brakeman 0 warnings; Zeitwerk; frontend lint/format/types, 73 Vitest and Next production build passed | `/tmp/phase10-check-final.log` |
| Browser/runtime | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e`; API/Compose smokes | 7/7 Playwright; sequential, concurrent, proxy, two-process idempotency and multi-process closing passed; closer restarted | `/tmp/phase10-browser.log`, `/tmp/phase10-smoke-*.log` |
| Native Kafka and dependency security | Host `rdkafka` delivery via 127.0.0.1:29092; duplicate receipt query; `bin/bundler-audit` | Host listener worked; duplicate retained one receipt/audit; no vulnerabilities found | `/tmp/phase10-native-kafka.log`, `/tmp/phase10-bundler-audit.log` |
| Final running consumer with reviewed code | Restart `kafka-audit-consumer`, rerun `scripts/smoke-kafka` | Auction 225 revision 3, three Kafka acknowledgments and receipts; broker healthy | `/tmp/phase10-final-smoke-kafka.log` |
| Final documentation and repository state | Relative Markdown link check over 72 files; `git diff --check`; coherent commits and clean tree | 0 missing links; 0 whitespace errors; implementation commit `874deb7`; documentation committed with this plan | Final local checks, 2026-09-30 |

## Final adversarial review

- **Authority and atomicity:** Kafka clients are constructed only in dedicated
  publisher/consumer roles. `Auction#persist_public_change!` writes the snapshot
  before its transaction exits; a failed insert rolls back the mutation and
  enclosing command outcome. Kafka delivery and audit never write Auction, Bid,
  MaximumBid or IdempotencyRecord. Real broker and Redis outages left bid truth
  committed; neither transport decides a winner.
- **Privacy and schema:** Snapshot fields are public auction fields; strict
  codec allowlists exact envelope/data keys and rejects unknown version/type or
  wrong partition key. Logs include event UUID, partition/offset and error
  class, not payload, raw key, private maximum, priority or origin. The local
  plaintext broker is loopback published and is not a production security
  design. A v1 incompatibility needs a new version/topic review.
- **Concurrency, crash and replay:** PostgreSQL unique keys and transaction
  boundaries protect one audit effect per ID/revision. The two-connection
  duplicate race spec proves the second session waits on the receipt and
  returns `:duplicate`. Producer SIGKILL and consumer SIGKILL experiments prove
  both ambiguity windows. Concurrent publishers may reorder same-auction
  events despite a stable partition key; audit labels stale/gap without
  changing current state. Increasing partition count may remap keys.
- **Failure recovery:** Failed sends persist attempts/backoff. Poison stops
  the group at an uncommitted offset with no automatic restart policy; the
  tested operator reset skipped one reviewed invalid record. A valid record
  after poison waited, while PostgreSQL and both publishers continued. Kafka
  and Sidekiq share outbox row locks, so a slow Kafka send can temporarily
  delay a same-row hint claim. Broker retention, one replica, missing alerts,
  post-enqueue Cable loss and lack of production capacity remain material
  limits, documented in the runbooks and handoff.
- **Verification integrity:** All four temporary sabotage mutants were
  restored byte-identically; focused suite and final broad gate passed.
  Hosted CI and production failure/throughput claims remain unverified.
