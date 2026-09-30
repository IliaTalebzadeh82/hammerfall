# Current handoff — Phase 11 primary implementation checkpoint

Updated: 2026-09-30. **Phase 11 — Redis Projection is in progress.** Read the
[Phase 11 ExecPlan](../plans/phase-11-execplan.md), [Phase 11 specification](../phases/phase-11.md)
and [projection architecture](../architecture/projections-and-reconciliation.md)
for scope, decisions, Evidence Index and exact next action. Phase 12 has not started.

## Current state

Phase 10's PostgreSQL outbox and Kafka v1 public snapshots remain unchanged.
A separate `hammerfall.projection.v1` Kafka group validates events and writes a
versioned public-only Redis key through an atomic revision compare-and-set.
Duplicates and stale revisions cannot regress it; same-revision conflicting data
blocks offset commit. The explicit eventual `/api/v1/auctions/:id/public-state`
endpoint serves a lean Redis view with revision/source/age metadata and falls
back to PostgreSQL on miss, invalid data or Redis failure. Existing REST GET,
all commands and auction correctness remain PostgreSQL-backed. A manual
PostgreSQL seed script supports recovery after Redis loss. No Phase 12 scheduled
repair/reconciliation exists.

## Evidence and next action

20 focused examples passed with real local PostgreSQL/Redis (seed 41577), along
with Zeitwerk, changed Ruby lint, Compose config and whitespace checks. An
initial test invocation lacked the local PostgreSQL password; sourcing `.env`
resolved it. There is **no live Kafka-to-Redis verification yet**, nor real
Redis loss, process crash, replay, sabotage, broad regression or final docs.
The next session must start the Compose projection consumer and prove a real
event through Kafka to Redis and the eventual API, then run the live failure
campaign. Broker retention, publisher reordering and pre-Phase-10 rows limit
Kafka-only replay; PostgreSQL remains the current-state rebuild source.
