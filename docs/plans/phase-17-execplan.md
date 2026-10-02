# Phase 17 — Multi-Instance Deployment ExecPlan

Status: active; Session 2 checkpoint. Phase 18 excluded.

Current milestone: completed live cross-process realtime, loss/rejoin, ambiguity and deadline campaigns. Stop at this checkpoint; Session 3 owns final closure gates and the observed socket-reconnection limitation.

Completed: Session 1 two-container/proxy topology and command proof; Session 2 cross-instance Cable and browser REST recovery, missed hint, stop/rejoin, committed and pre-commit crash retries, soft close, deadline and closer races. Starting commit `44eb6cef8a941faa1d77da61130666b11b0d11dd` for the phase; Session 2 started at `0efedbba69a3bc0bf12ea3a925007fe17473cc65`. [Session 1](../multi-instance/session-1.md) and [Session 2](../multi-instance/session-2.md) reports carry retained evidence and invalid harness attempts.

Verified: Session 1's three command runs and 80 focused examples; Session 2's browser/CDP and direct PostgreSQL campaigns; 82 focused real-PostgreSQL RSpec examples, zero failures (seed 39585); targeted RuboCop, Biome lint/format, Ruby/Python/Node syntax, nginx and Compose validation and diff check. Hosted CI and full gates unrun.

Remaining: Session 3 investigate variable automatic Cable reconnection after stopping the socket-owning container; run full backend/frontend gates, clean Compose recreation, runtime/browser regression, hosted CI, final architecture/adversarial review and phase closure. Do not repeat passing Session 1/2 campaigns without a concrete invalidation. Phase 18 remains excluded.

Known failures/limitations: Session 1 harness/proxy corrections are in its report. Session 2's initial lock observer cached PostgreSQL activity and then missed a transitive waiter; corrected proof observed two waiters. A Python header-case assertion was fixed. The socket disconnected on replica stop; one run resubscribed on `a`, while later runs did not reconnect within 30 seconds. Browser visibility REST recovered the committed state in those runs. No domain correctness failure observed. Local two-replica proof is not production availability or capacity evidence.

Relevant files: `docker-compose.yml`, `infrastructure/{api-proxy,nginx-local}.conf`, `apps/api/config/cable.yml`, `apps/api/app/{models/auction.rb,services/auction_publication.rb,services/idempotency/executor.rb}`, `apps/web/src/{components/auction/auction-detail.tsx,lib/realtime/auction-subscription.ts}`, three Phase 17 harness scripts, `.github/workflows/ci.yml` and focused integration specs.

Relevant ADRs: ADR-003 (auction lock), ADR-004 (proxy bidding), ADR-005 (deadline), ADR-006 (idempotency), ADR-008 (Cable).

Next-session starting point: read this plan, handoff and [Session 2 report](../multi-instance/session-2.md). Investigate the observed automatic reconnect variability using the existing browser harness and Action Cable monitor behavior; preserve REST recovery. Then perform one final broad verification/hosted CI/review pass and close Phase 17 only if all gates hold. Do not start Phase 18.

## Decisions

- Use two explicit API containers and one small reverse proxy on the existing external API port. Preserve the `api` service name for operational jobs and existing direct Compose commands. Route ordinary web/client requests through the proxy without affinity.
- Use a fixed, local-only logical replica label in a diagnostic response header. It must not enter command or domain state.
- Keep one operational closer and one reconciliation scheduler. Their authoritative checks remain PostgreSQL transactions/locks and durable lease state, respectively.
- Add a local WebSocket upgrade response header with the upstream address solely for browser/CDP socket-owner attribution. The HTTP instance header remains diagnostic; no affinity or domain behavior changed.
- Treat observed socket interruption and sometimes delayed/absent 30-second resubscription as expected realtime degradation for this checkpoint. REST/focus recovery is proven; final review should decide whether a client reconnect change is warranted.

## Process-local audit

| Finding | Classification | Reason |
| --- | --- | --- |
| Development `:memory_store` cache | SAFE PROCESS-LOCAL | No auction command or ordinary GET reads it for authority. |
| Puma threads, PID/control socket and opt-in CPU profiler | SAFE PROCESS-LOCAL | Runtime diagnostics and local process management only. |
| Observability counters/tracing configuration | SAFE PROCESS-LOCAL | Metrics, traces and logs do not decide commands. |
| Auction, bid sequence, maximum priority, public revision | SHARED BY DESIGN | PostgreSQL row lock, persisted rows and SQL uniqueness. |
| Idempotency claim/outcome and outbox intent | SHARED BY DESIGN | Persisted in PostgreSQL transaction with authoritative mutation. |
| Deadline decision | SHARED BY DESIGN | PostgreSQL `clock_timestamp()` after auction lock. |
| Realtime publication | SHARED BY DESIGN | Development Action Cable PostgreSQL adapter; hints crossed processes in live browser runs. |
| Closer process and reconciliation scheduler | SAFE PROCESS-LOCAL | Operational polling only; locked DB recheck and durable lease decide effects. |

No correctness-sensitive per-process map, mutex, sequence, idempotency record or maximum-bid state found in targeted `app`, `config` and `lib` search. Session 2 also confirmed session middleware is disabled and the scheduler uses a durable lease. Recheck any new code during final review.

## Evidence Index

| Scenario | Topology and request distribution | Expected invariant | Observed replica/process handling | PostgreSQL result | Derived/realtime result | Failure or race | Decision | Residual limitation / evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Initial audit | One existing API | No process-local authority | Source inspection | SQL protocols found | PostgreSQL Cable adapter | None found | PASS | Static audit; command proof below |
| Proxy distribution | localhost:3001 → nginx → `a`,`b` | Both Rails processes serve ordinary requests | Six GETs: `b,a,b,a,b,a` | No mutation | Not sampled | Default nginx worker count initially hit only `a` | PASS | Local two-replica topology |
| Sequential command chain | Same proxy; command labels alternate | Durable sequence, price, leader, revision | Seven command/read responses crossed processes | Three SQL bids, price 11,500, rev 5, correct leader | REST matched SQL | None | PASS | [Three runs](../multi-instance/session-1-runs.jsonl) |
| Concurrent hot auction | Ten barrier-released HTTP commands to both processes, three runs | No lost accepted bid or duplicate sequence | `a` and `b` handled requests in all runs | 3/6/6 accepted, SQL IDs matched accepted responses; final price 14,500, rev `2+accepted` | Not sampled | Stale low bids rejected | PASS | Exact lock overlap timing unmeasured |
| Equal-ceiling proxy tie | Maximum commands on opposite processes | SQL priority resolves tie | `a→b` or `b→a` | Priority 1/2, original leader at 30,000, rev 4 | GET omitted private keys | None | PASS | Concurrent distinct-maximum race remains existing focused integration evidence |
| Same-key concurrent claim and replay | Race across `a`,`b`, later replay opposite executor | One effect, historical response | One original 201 and one replayed 201 | One bid and one new idempotency record, rev 3 | Not sampled | None | PASS | Process-death ambiguity proven separately below |
| Focused backend | Real PostgreSQL test DB | Preserve command contracts | `RAILS_ENV=test` on API container | 80 examples, 0 failures, seed 41872 | N/A | Initial invocation omitted test env and correctly aborted | PASS | Five focused files only |
| Local static/runtime | Two API processes, proxy, web | Config valid and ordinary entrypoint works | nginx/Compose/Ruby/RuboCop passed | Existing `smoke-api` passed through proxy; auction 596 | Web root returned expected 307 | None | PASS | Browser ran in Session 2; hosted CI pending |
| Cross-replica Cable | Socket `a`/bid `b` and inverse | Hint crosses process; REST owns state | Upgrade upstream IP and bid label differ | Auction 597 rev/outbox 3; 599 later rev/outbox 4 | Browser received public revision 3 and REST fetched 3 | None | PASS | Local PG pub/sub; [Session 2](../multi-instance/session-2.md) |
| Missed hint REST | Socket `a`, bid `b`, Sidekiq paused | REST recovers absent hint | Bid committed while socket stayed connected | Auction 612 rev/outbox 4, two bids | No revision-4 hint before visibility GET; browser displayed €110 | Delayed notification | PASS WITH EXPECTED DEGRADATION | One scoped interruption |
| Socket owner loss/rejoin | Socket `b`, then stop/start `b`; `a` serves | Truth and commands survive owner loss | Socket closed; one run reconnected on `a`, others did not within 30 s | Auctions 599/615 retained bids and rev 4 | Focus REST reached rev 4; rejoined `b` read rev 4 | Visible interruption | PASS WITH EXPECTED DEGRADATION | Reconnect variability needs final review |
| Committed crash/replay | Initial `b` dies after SQL commit; retry `a` | One logical command effect | First 502, retry 201 replay | Auction 601 unchanged at retry: one bid, rev/outbox 3, one completed outcome | Not sampled | Process death | PASS WITH EXPECTED DEGRADATION | Local scoped crash hook |
| Pre-commit crash/retry | Initial `b` dies before commit; retry `a` | No partial effect, one fresh execution | First 502, retry fresh 201 | Auction 602 crash snapshot equal before; after retry one bid, rev/outbox 3 | Not sampled | Process death | PASS WITH EXPECTED DEGRADATION | Local scoped crash hook |
| Soft-close contention | Locked auction; bid `a` then bid `b` | Serialize extension on SQL state | Both 201, two SQL waiters | Auction 608 sequences 1/2, original fixed, effective +90, rev/outbox 4 | Not sampled | Cross-process lock chain | PASS | Two commands only |
| DB deadline contention | Locked auction; bids `a` and `b` waited before due | Post-lock DB time decides | Both 422 `auction_ended` | Auction 616 no bids, rev/outbox 2, two completed rejections | Not sampled | Release after DB deadline | PASS | Closer paused for isolation |
| Closer vs bid | API `a` and separate closer waited past due; later bid `b` | One coherent close; reject post-close bid | Both bids 422, closer finalized | Auction 618 closed once, no bid, rev/outbox 3, valid `closed_at` | Not sampled | Cross-process lock chain | PASS | One ordering; other order in focused RSpec |
| Session 2 checks | Live Compose, real PostgreSQL test DB | Preserve contracts and configurations | 82 RSpec examples, seed 39585, zero failures; static checks passed | 11 client backends during two-API lock wait against 100 max | Browser campaigns above | None | PASS | Full/hosted CI in Session 3 |
