# Phase 17 — Multi-Instance Deployment ExecPlan

Status: active; Session 1 checkpoint. Phase 18 excluded.

Current milestone: completed the initial cross-replica command proof. Stop at the checkpoint; Session 2 owns realtime, restart, ambiguity and deadline campaigns.

Completed: process-local audit; two API containers behind the existing external port; safe development replica header; sequential, concurrent, proxy tie and idempotency verifier; three retained live runs; normal proxy API smoke. Starting commit `44eb6cef8a941faa1d77da61130666b11b0d11dd`. [Session 1 report](../multi-instance/session-1.md) explains topology, evidence and invalid harness attempts.

Verified: six external GETs alternated `b,a,b,a,b,a`; three verifier runs passed all four scenarios with direct PostgreSQL checks; 80 focused RSpec examples, zero failures; targeted RuboCop, nginx syntax, Compose config, Ruby syntax, diff check and normal API smoke passed. Browser and hosted CI unrun.

Remaining: Session 2 cross-instance Cable/REST, stop/rejoin, committed-but-unanswered retry onto another replica, deadline/soft-close and closer/scheduler validation. Final session: broad regression, browser, clean Compose recreation, hosted CI, adversarial review and phase closure. Do not replay Session 1 without a concrete invalidation.

Known failures/limitations: initial proxy worker count caused one-sided low-volume routing; fixed with one local nginx worker. Internal host authorization and three verifier assumptions were corrected; see report. No domain correctness failure observed. The request barrier establishes concurrent dispatch across replicas, but the current trace does not quantify simultaneous row-lock overlap. Cable, failure/restart and deadlines are not yet proven across replicas.

Relevant files: `docker-compose.yml`, `infrastructure/{api-proxy,nginx-local}.conf`, `apps/api/app/controllers/api/v1/base_controller.rb`, `apps/api/config/environments/development.rb`, `apps/api/script/phase17_session1.rb`, `.github/workflows/ci.yml`, existing HTTP smoke scripts and integration specs.

Relevant ADRs: ADR-003 (auction lock), ADR-004 (proxy bidding), ADR-005 (deadline), ADR-006 (idempotency), ADR-008 (Cable).

Next-session starting point: read this plan, handoff and [Session 1 report](../multi-instance/session-1.md), inspect actual Cable and browser recovery implementation, then prove a WebSocket on one replica receives an invalidation from a mutation on the other. Continue through failure and deadline campaigns in that fresh session. Do not start Phase 18.

## Decisions

- Use two explicit API containers and one small reverse proxy on the existing external API port. Preserve the `api` service name for operational jobs and existing direct Compose commands. Route ordinary web/client requests through the proxy without affinity.
- Use a fixed, local-only logical replica label in a diagnostic response header. It must not enter command or domain state.
- Keep one operational closer and one reconciliation scheduler. Their authoritative checks remain PostgreSQL transactions/locks and durable lease state, respectively.

## Process-local audit

| Finding | Classification | Reason |
| --- | --- | --- |
| Development `:memory_store` cache | SAFE PROCESS-LOCAL | No auction command or ordinary GET reads it for authority. |
| Puma threads, PID/control socket and opt-in CPU profiler | SAFE PROCESS-LOCAL | Runtime diagnostics and local process management only. |
| Observability counters/tracing configuration | SAFE PROCESS-LOCAL | Metrics, traces and logs do not decide commands. |
| Auction, bid sequence, maximum priority, public revision | SHARED BY DESIGN | PostgreSQL row lock, persisted rows and SQL uniqueness. |
| Idempotency claim/outcome and outbox intent | SHARED BY DESIGN | Persisted in PostgreSQL transaction with authoritative mutation. |
| Deadline decision | SHARED BY DESIGN | PostgreSQL `clock_timestamp()` after auction lock. |
| Realtime publication | SHARED BY DESIGN | Development Action Cable PostgreSQL adapter; hints are derived. |
| Closer process and reconciliation scheduler | SAFE PROCESS-LOCAL | Operational polling only; locked DB recheck and durable lease decide effects. |

No correctness-sensitive per-process map, mutex, sequence, idempotency record or maximum-bid state found in targeted `app`, `config` and `lib` search. Recheck any new code during final review.

## Evidence Index

| Scenario | Topology and request distribution | Expected invariant | Observed replica/process handling | PostgreSQL result | Derived/realtime result | Failure or race | Decision | Residual limitation / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Initial audit | One existing API | No process-local authority | Source inspection | SQL protocols found | PostgreSQL Cable adapter | None found | PASS | Static audit; command proof below |
| Proxy distribution | localhost:3001 → nginx → `a`,`b` | Both Rails processes serve ordinary requests | Six GETs: `b,a,b,a,b,a` | No mutation | Not sampled | Default nginx worker count initially hit only `a` | PASS | Local two-replica topology |
| Sequential command chain | Same proxy; command labels alternate | Durable sequence, price, leader, revision | Seven command/read responses crossed processes | Three SQL bids, price 11,500, rev 5, correct leader | REST matched SQL | None | PASS | [Three runs](../multi-instance/session-1-runs.jsonl) |
| Concurrent hot auction | Ten barrier-released HTTP commands to both processes, three runs | No lost accepted bid or duplicate sequence | `a` and `b` handled requests in all runs | 3/6/6 accepted, SQL IDs matched accepted responses; final price 14,500, rev `2+accepted` | Not sampled | Stale low bids rejected | PASS | Exact lock overlap timing unmeasured |
| Equal-ceiling proxy tie | Maximum commands on opposite processes | SQL priority resolves tie | `a→b` or `b→a` | Priority 1/2, original leader at 30,000, rev 4 | GET omitted private keys | None | PASS | Concurrent distinct-maximum race remains existing focused integration evidence |
| Same-key concurrent claim and replay | Race across `a`,`b`, later replay opposite executor | One effect, historical response | One original 201 and one replayed 201 | One bid and one new idempotency record, rev 3 | Not sampled | None | PASS | Process-death ambiguity awaits Session 2 |
| Focused backend | Real PostgreSQL test DB | Preserve command contracts | `RAILS_ENV=test` on API container | 80 examples, 0 failures, seed 41872 | N/A | Initial invocation omitted test env and correctly aborted | PASS | Five focused files only |
| Local static/runtime | Two API processes, proxy, web | Config valid and ordinary entrypoint works | nginx/Compose/Ruby/RuboCop passed | Existing `smoke-api` passed through proxy; auction 596 | Web root returned expected 307 | None | PASS | No browser run or hosted CI yet |
