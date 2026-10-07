# Current handoff — Phase 23 closure

**Phase 22 complete. Phase 23 complete locally; exact-SHA hosted CI is the final closure gate. Phase 24 has not started.** Updated 2026-10-07 (Asia/Tehran). The [Phase 23 ExecPlan](../plans/phase-23-execplan.md) contains the claim/source register and verification details.

The [README](../../README.md) is the front door to the [case study](../case-study.md), its three evidenced stories, primary architecture diagram, [Catawiki public-behavior comparison](../catawiki-alignment.md), [10–15 minute walkthrough](../walkthrough.md) and [interview guide](../interview-guide.md). `./scripts/showcase` and the [demo guide](../demo.md) provide one repeatable local auction path through authentication, stepped increments, hidden reserve, proxy resolution, rapid extension, cross-replica same-key replay, autonomous close, PostgreSQL authority and Kafka/Redis convergence. PITR remains retained evidence, not an ordinary live-demo step.

Ordinary Compose startup from stopped containers passed. Three repeated showcase runs passed at 41.9/41.7/41.9 seconds; final output and uncached replay checks passed at 41.0/42.6 seconds. Focused API requests: 56 examples, 0 failures. Ordinary authenticated lifecycle smoke, targeted RuboCop, Bash/shellcheck, privacy scan, 331 local links/anchors and nine first-party Catawiki URLs passed. Two initial showcase timeouts were caused by Rails runner SQL query caching during cross-process polling and were fixed with uncached reads. No product code or schema changed. Production capacity, Catawiki internals, managed DR/cloud and Mermaid rendering remain unverified.

The closure commit must be pushed and hosted `api`, `web` and `compose` jobs must pass on that exact full SHA. Do not start Phase 24 without an explicit request.
