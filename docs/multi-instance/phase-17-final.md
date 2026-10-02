# Phase 17 — final multi-instance review

Date: 2026-10-02. Scope: two local Rails/Puma API containers behind one
loopback nginx proxy. [Session 1](session-1.md) retains the command runs;
[Session 2](session-2.md) retains cross-process Cable, crash and deadline
campaigns. This report is the concise conclusion, not a capacity study.

## Topology and authority

```text
                 API a
               /       \
client → nginx             → PostgreSQL authority
               \       /
                 API b
```

The proxy routes ordinary HTTP and WebSocket upgrades to either API without
sticky routing. A local diagnostic header identifies HTTP handling process;
the Cable upgrade header reports attempted upstreams. Neither enters domain
state. Each API is a replaceable executor. PostgreSQL row locks, unique
constraints, DB time, transactions, idempotency records, outbox rows and public
revisions decide auction outcomes. Redis, Kafka, Sidekiq and Cable are derived
delivery paths. Replica-local Puma threads, development cache and diagnostics
hold no auction authority.

One operational closer discovers due auctions, but `close!` locks the auction,
samples DB time and rechecks state; concurrent closure is safe. One operational
reconciliation scheduler avoids duplicate polling, while PostgreSQL leases
fence scan ownership. Operational singleton counts are not correctness
singletons. API replication did not duplicate these background roles.

## Direct evidence

| Boundary | Result |
| --- | --- |
| Proxy distribution | Fresh stack: eight auction GETs alternated `a,b` and returned revision 4. No affinity. |
| Sequential and concurrent commands | Session 1 and final `phase17_session1.rb`: commands crossed replicas; ten concurrent bids yielded five accepted, five valid stale rejections in the final run, unique sequences and correct final price/leader/revision in PostgreSQL. |
| Proxy/max bids | Equal ceiling retained first priority; final proxy smoke covered settlement and private-field exclusion. |
| Idempotency | Same-key concurrent commands on different replicas made one effect; completed replay on the other returned the historical result. |
| Lost HTTP response | Session 2 killed `b` after commit: first response lost, same key on `a` replayed original 201 with no extra bid/revision/outbox row. A kill before commit rolled all SQL work back; same-key retry on `a` executed once. |
| Cable crossing | Socket `a` received a hint after mutation on `b`, and the inverse. The hint contained only `type`, `auction_id`, `revision`; browser REST fetched authoritative state. Fresh stack repeated both directions on auctions 643/644. |
| Replica loss/rejoin | Socket owner death interrupted Cable; surviving API served bids and reads. Resubscription on `a` and REST revision 4 were observed on fresh-stack auction 645. Rejoined `b` immediately served revision 4 without reconstruction. |
| Soft close and deadlines | Two locked cross-process bids serialized with one +90-second extension. Two waiters released after PostgreSQL time passed the deadline both received 422, without mutation. |
| Closer race | Autonomous closer competing with a waiting bid produced one coherent closed state and post-close rejection. Focused integration tests cover the opposite ordering and concurrent closers. |

## Reconnect investigation

The installed Action Cable client leaves its monitor running after an ordinary
socket close. It polls with jitter around a six-second stale threshold and
retains the subscription. The detail component does not dispose it on
disconnect. Subscription confirmation and visibility events each request REST
state. No frontend reconnect code was added.

CDP showed why Session 2's 30-second observations varied: Chrome made a new
Cable attempt, but its handshake stalled while nginx tried the dead container.
The `/cable` location lacked the five-second upstream connect timeout already
used by ordinary HTTP. The proxy now applies `proxy_connect_timeout 5s` to
Cable as well. Three post-change stop runs confirmed a new subscription on
`a`; the fresh-stack run observed close at 11:01:57 UTC, retry attempt at
11:02:12, nginx's `b,a` upstream chain and confirmation at 11:02:17. CDP's
upgrade header can list multiple attempted upstreams, so the harness now uses
the final address and filters out Next.js HMR sockets. It records creation,
attempt, handshake, close, confirmation and REST reads. The first instrumented
pre-fix run recorded a new Chrome attempt with no handshake within 30 seconds;
after the timeout change, retries completed through `a`.

This remains an interruption and retry, with no reconnect latency promise or
exactly-once hint delivery. A silently missed hint still needs a later REST
trigger. Cable conveys invalidation only; REST/PostgreSQL supplies truth.

## Final local gates

- Full real-PostgreSQL RSpec: 449 examples, 0 failures, 3 opt-in live-Kafka
  examples pending (seed 53371). Session 2 focused regression: 82 examples,
  0 failures. Final cross-replica runner passed sequential, concurrent, proxy
  tie and same-key cases.
- Frontend: Biome lint/format, Next typecheck, 73 Vitest tests and production
  build passed. Seven normal Chrome scenarios passed; one opt-in worker-outage
  scenario was skipped by its default gate.
- RuboCop, Brakeman (0 warnings), dependency audit (0 known vulnerabilities),
  Zeitwerk, Ruby/Python/Node syntax, nginx syntax, Compose config and
  `git diff --check` passed.
- `docker compose down` then `up --build --wait` started both APIs, proxy,
  PostgreSQL, Redis, Kafka, Sidekiq, both publishers, both consumers, closer,
  scheduler and frontend healthy. Proxy `/up`, Kafka/Redis, lifecycle,
  concurrent bidding, proxy bidding, closer, scheduler and publisher one-shots
  passed. The final CDP runs verified both socket/mutation directions, loss,
  REST recovery and rejoin.
- A final `pg_stat_activity` snapshot found 13 development client sessions
  against `max_connections=100`, including the local sampler: API `a` four,
  API `b` one, eight other/local sessions. Each API's configured Active Record
  pool is three, so two such pools can reserve six connections; Cable and
  background roles add connections. This is a point observation, not a limit
  or tuning recommendation.

## Adversarial review and limits

The final audit found no replica label in bid, priority, deadline, winner,
idempotency or outbox logic. Nginx has no sticky routing and does not opt into
retrying a non-idempotent POST after sending it upstream. A failed connect can
retry another upstream before execution; an ambiguous committed command still
requires the same client key and payload. No process-local map, mutex, timer or
diagnostic header decides an auction outcome. The only closure change is the
Cable proxy timeout and corrected observation harness. No Phase 18 work began.

This proves correctness under two local API processes. It does not prove
linear throughput, production capacity, Kubernetes or autoscaling behavior,
large replica counts, PostgreSQL failover, cloud load-balancer behavior,
regional failover, zero interruption or exactly-once WebSocket delivery. More
APIs can send more concurrent work to shared PostgreSQL, raising hot-row and
connection contention. Phase 17 did not tune pools or redesign ordering.

Hosted CI evidence: pending closure commit.
