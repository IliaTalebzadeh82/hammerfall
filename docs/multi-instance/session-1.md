# Phase 17 Session 1 — local cross-replica command proof

Date: 2026-10-02. Starting commit: `44eb6cef8a941faa1d77da61130666b11b0d11dd`.
This is local Compose evidence, not a capacity, cloud availability or production claim.

## Topology and ownership

`localhost:3001` now reaches one nginx proxy and two distinct Rails/Puma
containers (`api` = `a`, `api-replica-b` = `b`). The frontend's server-side API
origin reaches the same proxy. The proxy uses one worker and round-robin
upstreams without cookie or IP affinity; it forwards WebSocket upgrades. A
development-only `X-Hammerfall-Instance` response header reports a bounded
logical label. The header has no role in bid, retry, deadline or publication
decisions. Existing closer, Sidekiq, publishers, consumers and reconciliation
scheduler remain separate operational roles, each with its previous replica
count. The single closer polls for candidate IDs but locks and rechecks
PostgreSQL state/time before closing. The scheduler's lease is durable in
PostgreSQL, so its one process limits redundant scans rather than defining
auction correctness.

Source audit found no auction authority in class variables, globals, mutexes,
request caches, local files or per-process maps. Development's memory cache,
Puma control socket and profiling thread are local diagnostics/performance
state. Auction rows, accepted sequence, maximum priority, revision, command
record/outcome and outbox intent are in PostgreSQL. Deadline decisions use
PostgreSQL time after lock acquisition. Development Cable already uses the
PostgreSQL adapter; live cross-instance Cable delivery remains to be tested.

Two API processes with default pool size 3 can reserve up to six API database
connections, in addition to the separate background roles and one-off tasks.
The sampled local `pg_stat_activity` showed 14 client backends, 1 active, with
`max_connections=100`; it is a snapshot, not a capacity result. No PostgreSQL
limit or pool size was raised.

## Evidence

The retained [three runs](session-1-runs.jsonl) used one stable proxy URL for
every command, a fresh connection per request, diagnostic replica headers, and
uncached direct PostgreSQL checks. Every run passed all four scenarios.

| Scenario | Request distribution | Expected invariant and authoritative result | Derived/realtime result | Failure or race observed | Decision and residual limit |
| --- | --- | --- | --- | --- | --- |
| Sequential lifecycle, bids and maximum | Seven command/read responses alternated `a/b` or `b/a` | Three accepted sequences `[1,2,3]`; price 11,500, original bidder leading, public revision 5; REST agreed with SQL | Not sampled | None | PASS; two replicas only |
| Ten simultaneous bids on one auction | Both replica labels in every run | 3, 6 and 6 accepted; each response bid ID matched one SQL row; sequences contiguous, price 14,500, highest bidder leading, revision `2 + accepted` | Not sampled | Stale lower bids rejected as designed | PASS; request barrier proves concurrent dispatch, not exact row-lock overlap timing |
| Equal maximum ceilings | Two commands reached different replicas in each run | SQL priority `[1,2]`, original bidder retained lead at 30,000, bid amounts `[10000,30000,30000]`, revision 4 | Public GET contained no maximum, priority or origin key | None | PASS; no concurrent maximum race in this scenario |
| Concurrent same-key bid and completed replay | Racing requests reached `a` and `b`; completed replay reached the process opposite the original executor | One bid, one new idempotency row, matching 201 bodies, one replay among racing requests; later replay remained historical; revision 3 | Not sampled | SQL unique ownership arbitrated race | PASS; committed-but-unanswered process death remains for Session 2 |

The initial six external GETs all reached `a` even with two containers. Nginx's
default `worker_processes auto` started many workers, each with its own initial
round-robin state. Setting one local proxy worker made six repeated GETs alternate
`b,a,b,a,b,a`. This was a topology failure, not auction correctness evidence.
The first internal verifier request also received Rails host-authorization 403
for `api-proxy`; explicit development host entries fixed the route.

Two verifier assertions were corrected before retained evidence: new auctions
begin at public revision zero (so activation is revision 2), and matching
`original_ends_at` against the private `origin` key was too broad. A later SQL
effect-count assertion saw the runner's query-cache result from before external
HTTP writes; the checker now uses uncached database reads. An initial same-key
replay could land on its original replica due to round-robin parity; the
verifier issues bounded safe replays until it sees the opposite replica.
The failed harness attempts are not counted as passes; no application-domain
correctness failure was found.

Focused real-PostgreSQL RSpec passed: 80 examples, zero failures, seed 41872,
covering concurrent bids, concurrent maximums, concurrent idempotency and
request contracts. Targeted RuboCop inspected two changed Ruby files without
offenses. `nginx -t`, `docker compose config --quiet`, Ruby syntax and
`git diff --check` passed. The proxy `/up` returned 200 and the frontend
root returned its expected 307 redirect. The established sequential API smoke
via the proxy is recorded in the ExecPlan after it finishes. Hosted CI has a
new cross-replica correctness step but has not run yet.

## Remaining work

Next sessions must directly test cross-instance Cable/REST recovery, replica
stop/rejoin and ambiguous retry, deadline/soft-close races, closer/scheduler
ownership under failure, and final broad regression/browser/hosted CI. Static
inspection and these four command campaigns do not prove those cases.
