# Current handoff — Phase 12.5 in progress

Updated: 2026-10-01. Phase 12.5 is the explicitly requested correctness and
production-hardening pass over completed Phase 0–12. Phase 13 has not begun.
Read `AGENTS.md`, the [Phase 12.5 specification](../phases/phase-12-5.md) and the
active [ExecPlan](../plans/phase-12-5-hardening-execplan.md); it holds the finding
ledger, decisions and Evidence Index. Use the [context map](../context-map.md)
only to route targeted remaining work. Do not reconstruct prior sessions.

Session 1 (`59e1229`) repaired public snapshot semantic validation, outbox
occurrence time and model readonly event fields, delayed reconciliation lease
expiry, structural outbox SQL checks, and the production host default. It passed
44 focused and 78 adjacent integration examples, changed Ruby lint, Zeitwerk
and a production host boot check. New occurrence semantics apply only to new
outbox rows. PostgreSQL remains auction authority.

Session 2 retained the existing transaction-held Sidekiq and Kafka publishers
after controlled real PostgreSQL contention showed same-row cross-path delay
but progress on different rows. Each publisher process holds at most one outbox
row and connection at a time; there is no strict whole-cycle external-I/O
deadline or measured production capacity. Live Kafka failure persisted retry
state and real broker recovery acknowledged the same event. Tests also covered
publisher exit before enqueue, database acknowledgment rejection after Redis
acceptance, and safe duplicate retry. An ack-before-delivery sabotage failed
its test and was restored. The two publishers' delivery states remain
independent; no lease/claim redesign or auction protocol change was made. See
[ADR-010](../adr/010-transactional-public-outbox.md) and
[ADR-011](../adr/011-kafka-domain-events.md).

Session 2 explicitly deferred HMAC conversion: unkeyed SHA-256 exposes weak
client keys to offline guessing after database theft, but retained unversioned
rows need a replay-preserving migration and shared secret rotation design.
The missing pre-parse request-size limit is a public-ingress blocker; a safe
streaming limit belongs with the later security/deployment work. The demo API
remains unauthenticated and must not be exposed publicly. Publisher defaults
now appear in `.env.example`; the runbooks/readiness guidance describes
connection and lock occupancy. Focused checks passed: 18 Kafka outbox examples
with live broker, 13 transactional outbox examples, 51 idempotency examples and
changed Ruby lint. Full details and sabotage restoration are in the ExecPlan.

Next fresh session: run the final Phase 12.5 gates—complete backend/frontend
regression, browser E2E, Compose full-stack, Brakeman, dependency audit,
production build, hosted GitHub Actions, documentation reconciliation and
final adversarial review. Fix discovered failures, record actual evidence,
then close Phase 12.5 if its definition of done is met. Do not begin Phase 13.
