# Phase 17 Session 2 — process loss, realtime and deadline proof

Date: 2026-10-02. Starting commit: `0efedbba69a3bc0bf12ea3a925007fe17473cc65`.
Local Compose evidence only. Phase 17 remains active; Phase 18 is excluded.
The repeatable harnesses are `apps/web/scripts/phase17_session2_realtime.mjs`,
`apps/api/script/phase17_session2_ambiguity.py` and
`apps/api/script/phase17_session2_deadlines.rb`. The browser harness uses Chrome
DevTools' WebSocket handshake response, the proxy's local upstream diagnostic
header and Docker's container IP mapping to identify the socket owner. HTTP
commands use the existing bounded instance response header. Neither header
influences auction state or routing.

## Cable topology and browser recovery

Development and production `cable.yml` select the PostgreSQL pub/sub adapter;
test uses the test adapter. `AuctionChannel` streams `auction:<id>`.
`AuctionChangedJob` reads the committed public revision and
`AuctionPublication.broadcast` sends only `type`, `auction_id`, `revision`.
PostgreSQL NOTIFY fans this stream to subscribed Action Cable processes. The
browser's `RefreshCoordinator` treats a hint as invalidation, calls the normal
PostgreSQL-backed `GET /api/v1/auctions/:id` and the bids GET, then accepts only
a nonregressing REST revision. Subscription confirmation and visibility changes
also trigger REST reads. No command outcome is inferred from Cable.

| Scenario | Topology and replica handling | Injected failure/race; expected invariant | Observed HTTP/Cable and browser | Direct PostgreSQL verification | Decision; residual limitation |
| --- | --- | --- | --- | --- | --- |
| Cross-process Cable | Browser socket `a` (`172.18.0.6`), bid via proxy `b`, auction 597; inverse socket `b` (`172.18.0.18`), bid `a`, auction 599 | Mutation and socket on different Rails processes; shared hint, REST authority | 597: hint revision 3, browser REST revision 3; 599: hint 3, browser REST 3. Only three public hint keys; browser price rendered from REST. | 597: one bid ID 8302, price 10,000, leader 4039, revision/outbox 3/3, one completed command. 599 later continued below. | **PASS**; local PostgreSQL Cable adapter, not a network partition test. |
| Missed hint | Socket `a`, mutation `b`, auction 612; Sidekiq stopped after initial hint, then a second bid committed | No revision-4 hint before recovery; REST remains correct | Initial hint/REST 3. While worker stopped, browser visibility refresh fetched revision 4 via `b` and displayed €110.00; received hint maximum was still 3. Worker restarted. | Two bids IDs 8321/8322 in sequences 1/2, price 11,000, leader 4062, revision/outbox 4/4, two completed commands; no maximums. | **PASS WITH EXPECTED DEGRADATION**; one bounded missed hint, not the full Phase 16 worker-outage campaign. |
| Owning replica stops | Browser socket `b`, proxy serves `a` after `b` stops; auction 599 | Socket must disconnect without losing auction truth; continued commands and GETs must work | Socket closed, then a new handshake and confirmation on `a` in the successful 599 run. A new bid ID 8305 returned 201 from `a`; browser REST read revision 4. | 599: bid IDs 8304/8305, sequences 1/2, price 11,000, leader 4041, revision/outbox 4/4, two completed commands. | **PASS WITH EXPECTED DEGRADATION**; visible WebSocket interruption. |
| Delayed socket recovery | Same topology, auctions 614 and 615 | If reconnection is delayed, explicit browser REST recovery must still see committed state | In each run the `b` socket closed but no new handshake was observed within 30 seconds. A bid on `a` returned 201 and a visibility-triggered browser REST GET read revision 4 and displayed €110.00. | 615: bid IDs 8326/8327, sequences 1/2, price 11,000, leader 4065, revision/outbox 4/4. | **PASS WITH EXPECTED DEGRADATION** for authority/REST; automatic reconnection timing is inconsistent and needs final-session investigation. Do not claim uninterrupted Cable failover. |
| Replica rejoin | Stop then start `b`; proxy stays up | `b` must read current SQL state without warm-up | Proxy returned 200 from `b` with revision 4 after restart for auctions 599, 614 and 615. The healthy `a` served the outage. | Same auction revisions and bid histories before/after rejoin; no state reconstruction. | **PASS WITH EXPECTED DEGRADATION**; nginx may return one failed request while learning a stopped upstream. This is local replica loss, not production HA. |

The first stop run closed the socket but did not resubscribe within its bound;
it was **invalid as automatic-reconnect proof**. A later run did resubscribe on
`a`. Two further runs again lacked a new handshake within 30 seconds and were
retained as REST-recovery evidence. The Phase 17 claim is that socket death
does not remove auction truth, not that reconnect has a fixed latency.

## Ambiguous command on another replica

For each case, a scoped Phase 16 development-only hook targeted a new auction
on `b`. `a` was temporarily stopped, so the initial request through nginx had
only `b` available and could not be silently retried on `a`. Nginx returned
502 after `b` exited. The same key and payload were retried through nginx after
`a` restarted, with its diagnostic label proving the new executor. A separate
closer-container Rails runner queried PostgreSQL before, immediately after the
crash and after retry. Both API containers and the proxy were restored from
base Compose configuration afterward.

| Scenario | Failure boundary; expected invariant | Observed HTTP and replica handling | Direct PostgreSQL verification | Decision; residual limitation |
| --- | --- | --- | --- | --- |
| Committed but unanswered, auction 601 | `command_committed` exits `b` after the outer SQL transaction, before response | First HTTP 502; same-key retry on `a` returned original 201 with `Idempotency-Replayed: true` and bid ID 8307 | At crash and after retry: one bid sequence 1, price 10,000, leader 4043, revision 3, outbox 3, one completed record with original 201 body. Before: zero bids, revision/outbox 2/2. No additional row, sequence, priority, revision, event or deadline change on replay. | **PASS WITH EXPECTED DEGRADATION**; intentional brief loss of both APIs to force the first route. |
| Before commit, auction 602 | `command_before_commit` exits `b` inside the open outer transaction | First HTTP 502; same-key retry on `a` returned fresh 201 without replay header, bid ID 8309 | Snapshot after crash equaled before: zero bids/maximums/completed records, price 10,000, no leader, revision/outbox 2/2, unchanged deadlines. After retry: one bid sequence 1, leader 4044, revision/outbox 3/3 and one completed record. | **PASS WITH EXPECTED DEGRADATION**; PostgreSQL rollback and cross-replica execution, one fixture. |

An earlier completed-crash harness run reached the same SQL outcome but its
assertion used mixed-case response header lookup against Python's normalized
lower-case header map. That assertion failure was a harness error, not a domain
failure. The corrected two-boundary run above passed. No raw idempotency key is
retained in the report.

## Database-clock races and operational roles

The race runner held a real auction row lock in one SQL transaction, dispatched
HTTP bids directly to `api` and `api-replica-b`, and observed PostgreSQL lock
wait chains before releasing. Direct per-replica URLs made the process split
deterministic; ordinary client traffic still uses the proxy. It used actual
`clock_timestamp()` for the deadline boundary, without client timestamps or a
mock clock. The autonomous closer was stopped for the isolated soft-close and
deadline runs, then restarted for the closer race.

| Scenario | Topology and race; expected invariant | Observed HTTP/Cable/REST | Direct PostgreSQL verification | Decision; residual limitation |
| --- | --- | --- | --- | --- |
| Soft close, auction 608 | Requests on `a` and `b` both waited in the same lock chain; initial deadline 08:15:39.109984 UTC, holder released at DB time 08:15:09.204304 | Both returned 201 on their expected replicas. Cable/browser not sampled. | Bid IDs 8317/8318, sequences 1/2, amounts 10,000/11,000; price 11,000, leader 4056, revision/outbox 2→4, completed outcomes 2. `original_ends_at` stayed 08:15:39.109984; `ends_at` became 08:17:09.109984, exactly +90 seconds. The second bid saw the extended deadline and did not extend again in this timing. | **PASS**; a bounded two-command schedule, no capacity claim. |
| Deadline after lock, auction 616 | Both replicas were confirmed waiting before expiry; holder released at DB time 08:24:15.139961, after deadline 08:24:15.129509 | Both returned 422 `auction_ended`. Cable/browser not sampled. | No bids/maxima/leader/winner/closure; price 10,000, original/effective deadline unchanged, revision/outbox stayed 2/2. Two durable completed 422 outcomes. | **PASS**; isolates bid decision from closer by stopping its polling. Existing focused tests cover a waiting command after closer wins. |
| Closer vs bid, auction 618 | API `a` bid was confirmed waiting before expiry; it and the separate autonomous closer both waited in the held auction lock chain past due time | `a` returned 422 `auction_ended`; closer finalized; a later bid on `b` returned 422 `invalid_auction_state`. | Status closed; no bids or winner, price 10,000, `closed_at` 08:27:33.596926 after `ends_at` 08:27:33.494910, revision/outbox 2→3, two completed rejected commands. No hybrid state or post-close bid. | **PASS**; one observed ordering. Existing `concurrent_closing_spec` also proves extension-first recheck, closed-first rejection and eight simultaneous close calls. |

The first lock observer mistakenly reused Rails' query-cached
`pg_stat_activity` result; a second version only counted direct blockers and
missed a second API waiting behind the first. These runs were invalid as
two-waiter proof. The corrected observer clears PostgreSQL's statistics
snapshot, runs uncached and counts direct plus transitive blockers. Its passing
runs observed two blocked connections. A PostgreSQL lock chain establishes
serialization, not throughput or lock-wait distribution.

`Auction#close!` takes the same auction row lock, samples `AuctionClock.now`
after acquiring it, rechecks state/deadline and returns harmlessly if already
closed. The real-PostgreSQL eight-closer focused example passed; duplicate
closure safety does not depend on one polling process. `AuctionCloser` only
discovers candidates and calls that method. `ReconciliationScheduler` runs as
one operational process, but its scans claim durable `ReconciliationLease`
rows; API replicas neither schedule scans nor own the lease. The API app has
session middleware disabled, no cookie-backed auction authority, and no
per-process command cache. A second targeted audit found no new process-local
correctness dependency.

## Verification and limits

Representative commands from the repository root (the crash script and stop
scenario intentionally restart local Compose services):

```sh
(cd apps/web && MISS_HINT=true PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome node scripts/phase17_session2_realtime.mjs)
(cd apps/web && SOCKET_TARGET=b STOP_SOCKET_OWNER=true PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome node scripts/phase17_session2_realtime.mjs)
python3 apps/api/script/phase17_session2_ambiguity.py
docker compose stop auction-closer
docker compose exec -T -e MODE=soft_close api bin/rails runner script/phase17_session2_deadlines.rb
docker compose exec -T -e MODE=deadline api bin/rails runner script/phase17_session2_deadlines.rb
docker compose start auction-closer
docker compose exec -T -e MODE=closer_race api bin/rails runner script/phase17_session2_deadlines.rb
```

- Focused real-PostgreSQL RSpec: 82 examples, zero failures, seed 39585,
  covering revisions/Cable publication, bid and idempotency concurrency,
  deadlines, soft close, closer and request replay.
- Targeted RuboCop: one new Ruby race script, zero offenses. Ruby syntax,
  Python compile, Node syntax, Biome format/lint, nginx syntax, Compose config
  and `git diff --check` passed. No domain source, schema or API contract was
  changed.
- A bounded `pg_stat_activity` snapshot during auction 619's two-API lock
  wait showed 11 client backends against `max_connections=100`. That additional
  soft-close run also passed: two accepted sequences, one +90-second extension,
  revision/outbox 4/4. A separate after-campaign IP snapshot counted `a` at
  three connections including the sampler and `b` at one. Two default API
  pools of three can reserve six connections. No pool, Puma or PostgreSQL
  limit changed.
- The proxy's `proxy_next_upstream` handled subsequent requests after a
  stopped upstream; the intentional crash request returned 502. No sticky
  routing or new scheduler/closer replica was introduced. This is a local
  failure result, not a production load-balancer health or capacity claim.
- Full regression, clean Compose recreation, hosted CI and final adversarial
  review remain for Session 3. Automatic WebSocket reconnection after a clean
  container stop is variable in the observed 30-second window; REST recovery
  on focus worked. Investigate that behavior before final closure.
