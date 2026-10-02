# Current handoff — Phase 16 active, Session 2 checkpoint

Updated: 2026-10-02. Phase 16 is active; Phase 17 has not started. Resume in a
fresh Codex conversation from the [ExecPlan](../plans/phase-16-execplan.md)
and [Session 2 report](../chaos/session-2.md). Session 1's already completed
outage campaigns are indexed in its [report](../chaos/session-1.md); do not
rerun them without a concrete gap.

Session 2 passed deterministic publisher death after Kafka acceptance/before
SQL acknowledgment and audit consumer death after DB effect/before offset.
The publisher retry actually duplicated broker delivery; both consumers
logged duplicate treatment, while durable audit effect stayed exactly once
and Redis did not regress. The consumer's receipt/effect committed while its
offset stayed behind; redelivery was deduplicated and advanced the offset.

API restart preserved auction and idempotency state, including maximum
priority behavior. A committed command with a lost response replayed its
original result after later state changes. An uncommitted command left no
partial state and executed once on same-key retry. With only the API stopped,
independent publishers and consumers drained backlogs and Redis converged.
Direct PostgreSQL checkers passed all retained campaigns. Local/test-only,
scoped crash hooks and bounded harnesses remain in source; production is
inert. Replay-short-circuit sabotage failed the expected test and was fully
removed. Relevant RSpec files passed 46 examples, 0 failures, 1 gated pending.

Four invalid Session 2 harness attempts are retained and explained in the
report. No Hammerfall correctness failure was observed. Browser WebSocket
receipt/REST recovery remains unobserved in this phase; Sidekiq job execution
and reconciliation scan progress during API outage were not counted. Full
regression, browser/runtime and hosted CI gates, final adversarial review,
documentation reconciliation and Phase 16 closure remain. Phase 17 requires
an explicit request. Do not infer any SLA from local recovery times.
