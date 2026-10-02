# Phase 18 Session 2 — live lifecycle and failure proof

Date: 2026-10-02. Started from pushed commit
`c7fb07877e3ea885f15fae93f209108930be6666` and the clean Session 1
checkpoint. This is the second hard checkpoint; Phase 18 remains in progress.
The local kind cluster and Compose dependencies from Session 1 stayed running.
No image or application behavior was changed. The only new executable is the
self-contained [Cable browser harness](../../apps/web/scripts/phase18_k8s_cable.mjs).

## Active API command and rollout

- Held auction 647's PostgreSQL row lock for 35 seconds, sent a keyed bid
  directly to one API pod, confirmed the request was waiting on a PostgreSQL
  transaction lock, then deleted that pod. Puma finished the request inside
  the 45-second termination grace: original response was 201. Retry through
  the web Service returned the same bid ID 8389 and
  `Idempotency-Replayed: true`. SQL showed price 10000, revision 3, one bid
  and one completed 201 idempotency record. This proves graceful completion
  for this bounded wait, not for requests lasting past the grace period.
- Enabled the existing development-only `command_committed` crash boundary
  on the API Deployment for auction 648, then sent a keyed bid through the
  web proxy. The first client received a non-JSON HTML error after its API
  process exited; the probe did not preserve the exact HTTP status. Previous
  pod logs showed `chaos_crash boundary=command_committed auction_id=648`.
  SQL showed one bid, price 10000, revision 3 and a completed 201 record.
  The same key through the web proxy returned the stored 201, bid ID 8390,
  with the replay header. The crash environment variables were removed and
  the API Deployment fully rolled out. This is a lost-response test after
  commit; it does not assert the original client observed success.
- A separate API rolling restart kept 100/100 `/ready` requests at HTTP 200
  through the Kubernetes API Service. A web rolling restart kept 100/100
  auction reads at HTTP 200 through the web Service and API proxy. Both
  Deployments returned to 2/2 Ready. The local `kubectl port-forward svc/web`
  disconnected when its selected web pod rolled; it was restarted. That
  port-forward is a developer access tunnel and is not evidence about Service
  availability.
- Scaled API 2→3 to Ready, then 3→2 during 100 internal auction GETs;
  100/100 returned 200. Desired replicas were restored to two. This is a
  bounded scale-down availability observation, not a throughput claim.

## Background roles and derived state

- Deleted the Sidekiq, Sidekiq outbox publisher, Kafka outbox publisher,
  audit consumer and projection consumer pods while 20 sequential bids were
  sent to auction 649 through the web proxy. All 20 returned 201. Replacement
  pods became Ready. SQL found 20 bids, 22 public outbox events, price 19500,
  revision 22, no pending Sidekiq or Kafka acknowledgments, 22 distinct
  Kafka audit entries and 22 consumed-event receipts. The explicit eventual
  API read returned Redis revision 22 and price 19500. This proves recovery
  after ordinary pod deletion during a small stream. It does not prove an
  exact in-flight Sidekiq job or publisher delivery interruption; their
  existing at-least-once crash-window tests remain the stronger boundary
  evidence. `Running` alone was not treated as progress.
- Scaled each Kafka consumer Deployment 1→2. Kafka group membership showed
  both members in each group with three partitions split 1/2. Six new
  auctions (650–655) each reached revision 3 with three matching outbox and
  audit rows, both publisher acknowledgments complete and Redis revision 3.
  Audit group offsets matched log-end offsets on all three partitions (lag
  zero at the sampled point). Scaled both groups back 2→1; new auction 656
  reached three audit entries and Redis revision 3 with no pending Kafka
  acknowledgments. The single-broker local group result is no availability
  claim for Kafka itself.
- Deleted the closer pod during a short-deadline campaign. Its replacement
  closed auction 658 after its database deadline; SQL showed closed, no
  winner, revision 3. Auction 657 contained a bid, which correctly extended
  its deadline by 90 seconds; the replacement later closed it with price
  10000, winner 4120, revision 4. This verifies replacement with and without
  a winner, including the soft-close policy.
- Deleted the reconciliation scheduler pod. Its replacement logged both
  `postgresql_state` and `projection` scans as enqueued; Sidekiq logs showed
  corresponding sweep/reconciliation jobs starting and completing. Both
  leases were absent after completion. This verifies a replacement cycle,
  not a forced death while holding a lease; the real PostgreSQL lease tests
  remain the ownership proof.

## Cable and resource behavior

The [browser harness](../../apps/web/scripts/phase18_k8s_cable.mjs) creates an
auction, opens its detail page through the kind web port-forward, records the
actual Cable handshake and subscription in Chrome CDP, deletes API pods until
the owning socket closes, then waits for resubscription and a fresh hint/REST
price. Run from the repository root with a web port-forward and
`PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome node apps/web/scripts/phase18_k8s_cable.mjs`.
The first run on auction 649 observed socket closure, a new 101 handshake and
subscription, hint revision 23 and updated price. After making the harness
self-contained, the second run on auction 659 observed original confirmation
at 14:05:02 UTC, closure at 14:05:03, new 101 handshake and confirmation at
14:05:16–17, and revision 3 hint at 14:05:17. The page showed the new price.
The browser used REST for authoritative state. This records an observed
reconnect, without a maximum reconnect delay or delivery guarantee.

`kubectl top` remains unavailable because metrics-server is absent. A single
cgroup snapshot after the campaigns found API memory 144 MB/1 GiB, web Node
68 MB/512 MiB, Nginx 24 MB/128 MiB, Sidekiq 131 MB/768 MiB, and each other
worker about 112–120 MB/512 MiB. All sampled containers reported zero
`oom`/`oom_kill` events. CPU throttling counters were nonzero for web and
workers, but no rate or time-series was measured; these values neither size
production resources nor establish load capacity. All application
Deployments ended at desired Ready replica counts, with no pending outbox
acknowledgments for auctions 647–659.

## Invalid attempts and remaining verification

- The initial Cable harness failed before opening Chrome because Playwright's
  bundled headless shell was not installed. The already installed
  `/usr/bin/google-chrome` was selected; both subsequent browser runs passed.
- A first lease query used nonexistent `lease_expires_at`; the schema uses
  `expires_at`. The corrected query showed no retained lease after jobs
  completed.
- The original attached continuation text was absent at its referenced path;
  only its initial excerpt existed in the attachment index. The repository
  handoff, ExecPlan and Phase 18 specification supplied the actionable scope.
- Session 3 still owns final adversarial review, relevant broad regression,
  lint/security/build gates, fresh-cluster setup, browser/runtime checks as
  needed, documentation/progress/handoff completion, and hosted CI. Verify
  the committed Cable harness and Kubernetes docs. No serious correctness
  failure was found in this session; capacity and long active-job shutdown
  remain unproven.
