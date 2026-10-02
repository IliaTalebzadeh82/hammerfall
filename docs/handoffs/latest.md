# Current handoff — Phase 16 complete; Phase 17 not started

Updated: 2026-10-02. Phase 17 — Multi-instance Deployment requires an explicit
request. Begin a future phase session with its [specification](../phases/phase-17.md),
this handoff and [context map](../context-map.md); do not replay Phase 16's
raw chaos runs by default.

Phase 16's [final report](../chaos/phase-16-final.md),
[gate record](../chaos/final-gates.md) and [closed ExecPlan](../plans/phase-16-execplan.md)
index the evidence. Verification commit
`179e5189c2e68e0890a0c1f433cb2125d11e6ea9` passed hosted
[CI run 36976775937](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36976775937):
API, web and Compose all succeeded. Local backend passed 449 examples, zero
failures and three gated pending; frontend passed 73 Vitest tests and seven
normal Chrome scenarios, plus the opt-in worker-outage browser scenario.

PostgreSQL remains the sole auction authority. A transaction commits bid,
revision, command outcome and immutable outbox intent together. Kafka
publication is at least once: a publisher crash after broker acceptance
actually duplicated delivery. Event-ID and revision guards kept audit effects
duplicate-safe and Redis from regressing. Consumer DB effects and Kafka
offsets are not atomic together. A committed-but-unanswered HTTP command
replays its original outcome on same-key/same-payload retry; pre-commit death
rolls back and the same retry executes once. Redis and realtime are derived.
Cable hints lead to REST refresh; a silently missed hint can leave an open page
stale until explicit refresh, visibility change, reconnect or a later hint.

These guarantees were observed in one-instance local Compose. Multiple API
instances, cross-instance races, network partitions, production failover,
Kubernetes and cloud behavior are **not** proven. Phase 17 should establish
those boundaries without changing existing lock, time, idempotency and outbox
protocols casually. Local/test-only crash hooks are inert by default and in
production, require exact scope and confirmation, and claim one-shot markers.
No chaos environment or sabotage remains in normal Compose.
