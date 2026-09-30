# Current handoff — Phase 11 live campaign checkpoint

Updated: 2026-09-30. **Phase 11 — Redis Projection remains in progress.** Read the
[Phase 11 ExecPlan](../plans/phase-11-execplan.md) and
[Phase 11 specification](../phases/phase-11.md) for exact evidence, limits and
remaining work. Phase 12 has not started.

## Current state

Primary implementation is committed as `b88ad58`: a separate Kafka projection
group writes versioned public-only Redis snapshots with atomic revision checks;
the explicit eventual public-state endpoint exposes freshness and falls back to
PostgreSQL; a manual PostgreSQL rebuild recovers disposable projection state.
Existing auction commands and ordinary GET remain PostgreSQL-backed. This
checkpoint adds a rebuild privacy regression. No production source mutation
from sabotage remains.

## Live evidence and next action

Real Compose Kafka → Redis → API delivery reached revision 3/10000 and then
4/11000. Duplicate and stale events did not regress state. During a Redis
outage, a bid committed in PostgreSQL at 5/12000 and the endpoint fell back;
the uncommitted event applied after restart. All 24 projection keys were lost
and 181 auctions were seeded from PostgreSQL; replay over the seed stayed at
5/12000. An isolated Redis DB was fully flushed and rebuilt to 6/13000. A
real abrupt consumer exit after writing revision 6 but before offset commit
left lag 1; restart replayed it as a duplicate and cleared lag. Concurrent
writes, private maximum exclusion, malformed-value fallback and four temporary
sabotage mutations were checked. The post-restore projection suite passed 8
examples, 0 failures (seed 50920), and the changed test passed lint.

The local Kafka topic held a Phase 10 poison event, so the new group stopped
at partition 1 offset 7 as designed. Its **local test** offsets were reset to
the tail before new events; PostgreSQL rebuild covered skipped history. This
operator recovery limitation, finite retention, eventual staleness and corrupt
key deletion need durable documentation. The shared Redis DB 0 was not fully
flushed because it contains other runtime state; the isolated DB 15 was.

**Next session:** review this checkpoint; run broad backend regression/lint and
relevant Compose/API runtime checks; finish ADR, architecture, API, operations,
invariants and learning/code-map/journal/progress documentation; perform final
adversarial review; commit coherent work; update this handoff and end at Phase 11.
