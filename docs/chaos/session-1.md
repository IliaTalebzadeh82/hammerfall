# Phase 16 Session 1 — local failure evidence

2026-10-02. Starting SHA: `2b9fb2fe2d7031c5a5b543afd48cf94e86ee540a`.
Normal Compose stack, one API instance, PostgreSQL, Redis, single-node Kafka,
independent publishers/consumers/workers, and optional observability services
were running. Each retained campaign used a new active auction, one bidder,
one baseline bid, and direct PostgreSQL verification. Recovery observation was
bounded to 120 seconds with five-second polls. Times below are **local observed
poll durations after restoration**, not SLOs.

## Evidence index

| Scenario | Run | Fault / observed recovery | Decision |
| --- | --- | --- | --- |
| Clean baseline | [784dea9d](p16-20261002T003553Z-784dea9d/) | None; full path converged in 6.13 s | PASS |
| Redis unavailable and fixture projection lost | [1d3bc497](p16-20261002T004412Z-1d3bc497/) | Stop Redis, then delete only the fixture projection key; first recovery 1.05 s, targeted reconciliation 1.13 s | PASS WITH EXPECTED DEGRADATION |
| Kafka broker unavailable | [edb14514](p16-20261002T003714Z-edb14514/) | Stop broker; restore and observe 17.38 s | PASS WITH EXPECTED DEGRADATION |
| Sidekiq and its outbox publisher stopped | [cfba7bd1](p16-20261002T003751Z-cfba7bd1/) | Stop both; restore and observe 0.61 s | PASS WITH EXPECTED DEGRADATION |
| Kafka publisher SIGKILL with broker down | [fbb18b64](p16-20261002T004652Z-fbb18b64/) | Two pending rows at kill; restart broker/publisher; bounded convergence recorded in timeline | PASS WITH EXPECTED DEGRADATION |
| Immutable event redelivered to live broker | [4423b674](p16-20261002T004331Z-4423b674/) | Both consumers logged `duplicate`; one receipt/effect and unchanged projection | PASS |

The [earlier Redis](p16-20261002T003635Z-51fc5d21/) and
[publisher](p16-20261002T004508Z-299539fa/) runs also passed; the retained
later runs add reconciliation, telemetry and full event-ID comparison. Three
preflight baselines (`9eab2a0d`, `e04fde66`, `ca8f6974`) failed or were
interrupted because the harness parsed the plain-text `/up` response as JSON,
misparsed a probe assertion, or compared the eventual response's extra public
metadata as if it were the projection payload. No fault was injected in these
preflight runs; the errors were fixed before retained campaigns.

## Redis loss and targeted repair

- **Precondition / injected fault:** Baseline auction 539 had revision 3,
  one bid, three outbox acknowledgments and three audit effects. Redis was
  stopped; another bid committed. After restart, only
  `hammerfall:auction-public:v1:539` was deleted to model loss of this derived
  snapshot without clearing the shared Sidekiq database.
- **Expected degradation / correctness:** Eventual GET should fall back to
  PostgreSQL; Sidekiq enqueue and projection can pause. Bidding, ordinary GET,
  revision and accepted history must remain PostgreSQL-correct.
- **Observed during fault:** PostgreSQL revision 4/two bids, one pending
  Sidekiq and Kafka outbox acknowledgment, audit at three effects. Eventual GET
  reported `source=postgresql` and the current public fields. The direct
  [during snapshot](p16-20261002T004412Z-1d3bc497/during.json) shows this.
- **Recovery / verification:** Redis and dependent workers restarted. Both
  outboxes drained, audit reached four, Redis revision/data matched the direct
  PostgreSQL probe. After deleting the fixture key again, the real reconciler
  returned `repaired` and the eventual endpoint again matched PostgreSQL.
  [Timeline](p16-20261002T004412Z-1d3bc497/timeline.json),
  [final snapshot](p16-20261002T004412Z-1d3bc497/final.json), and
  [checker](p16-20261002T004412Z-1d3bc497/verify.json) retain the evidence.
- **Duplicate/retry / limit:** This run did not establish whether Kafka replay
  or scheduled reconciliation won the first restoration race. The targeted
  second key deletion establishes reconciler repair. It does not prove a full
  Redis volume wipe, because this local Redis also stores Sidekiq state.

## Kafka broker outage

- **Precondition / fault:** Healthy auction 536 at revision 3, one bid and
  three audit effects; stop Kafka, then commit two more bids.
- **Expected degradation / correctness:** Kafka outbox and consumers lag;
  PostgreSQL commits and ordinary GET remain authoritative. No false Kafka
  acknowledgment is permitted while the broker is unavailable.
- **Observed during fault:** Revision 5/three bids committed. Two fixture
  Kafka outbox rows remained pending and audit stayed at three. Redis still
  served an older projection. [During snapshot](p16-20261002T003714Z-edb14514/during.json).
- **Recovery / verification:** Broker restart led to zero pending fixture
  rows, five audit receipts/effects and current Redis public fields in 17.38 s.
  Two rows showed repeat publisher attempts by recovery. PostgreSQL bid
  sequences, price/leader and outbox revisions passed the
  [checker](p16-20261002T003714Z-edb14514/verify.json).
  [Timeline](p16-20261002T003714Z-edb14514/timeline.json).
- **Limit:** This does not assert a fixed recovery time or broker durability
  beyond the local single-node named volume.

## Sidekiq notification path outage

- **Precondition / fault:** Healthy auction 537 at revision 3. Stop Sidekiq
  and its outbox publisher; commit two bids.
- **Expected degradation / correctness:** Realtime hints are delayed and
  Sidekiq acknowledgment backlog grows; commands and REST stay valid.
- **Observed during fault:** Revision 5/three bids committed; two Sidekiq
  outbox rows remained pending. The Kafka path also had two transient pending
  rows at this snapshot and caught up by recovery.
- **Recovery / verification:** Start worker and publisher. Both outbox counts
  reached zero, audit effects five and Redis matched PostgreSQL. Direct
  [checker](p16-20261002T003751Z-cfba7bd1/verify.json) passed;
  [timeline](p16-20261002T003751Z-cfba7bd1/timeline.json) records actions.
- **Duplicate/retry / limit:** The run proves durable enqueue backlog and
  recovery; it did not maintain a browser WebSocket subscription or count
  missing/resumed hints. Cable delivery remains invalidation with REST recovery.

## Publisher process death

- **Precondition / fault:** Healthy auction at revision 3. Stop Kafka, commit
  two more bids, then send SIGKILL to the Kafka outbox publisher while two
  fixture rows are pending. Snapshot immediately after the kill.
- **Expected degradation / correctness:** Kafka acknowledgments remain pending;
  no auction truth or immutable event identity changes with publisher lifetime.
- **Observed during fault:** PostgreSQL revision 5/three bids and two pending
  Kafka rows both before and after SIGKILL. The entire ordered outbox event-ID
  list remained identical. [Run](p16-20261002T004652Z-fbb18b64/).
- **Recovery / verification:** Restart Kafka and publisher. Pending count fell
  to zero, five unique audit receipts/effects existed, and Redis fields matched
  PostgreSQL. Event IDs remained identical and the direct checker passed.
- **Duplicate/retry / limit:** The kill occurred while the broker was down;
  it proves pending-backlog restart, **not** the crash-after-broker-acceptance /
  before-PostgreSQL-acknowledgment window. Session 2 needs deterministic
  orchestration of that window.

## Live duplicate delivery

- **Precondition / fault:** Auction 538 had revision 3, one bid and three
  audit receipts/effects. A Rails runner fetched its acknowledged immutable
  outbox envelope and deliberately published the same event ID to the live
  broker a second time, waiting for broker confirmation.
- **Expected degradation / correctness:** Consumers may see a repeat, but
  neither audit effect nor Redis revision/data nor auction truth may change.
- **Observed recovery / verification:** Audit and projection consumer logs each
  reported `result=duplicate` for the same event ID. Audit receipts/effects
  stayed at three, Redis stayed at revision 3, and direct PostgreSQL verification
  passed. [Audit log](p16-20261002T004331Z-4423b674/kafka-audit-consumer-duplicate.log),
  [projection log](p16-20261002T004331Z-4423b674/kafka-projection-consumer-duplicate.log),
  [snapshots](p16-20261002T004331Z-4423b674/).
- **Limit:** This is duplicate broker delivery of a valid event, not the
  consumer's post-DB-commit/pre-offset crash window; that remains for Session 2.

## Observability, privacy and next work

The later runs captured bounded Prometheus outbox pending/failure, Kafka lag
and projection drift queries beside direct state. These metrics are global and
scrape-sampled. For the short faults, `outbox_pending` often still read zero
when fixture-specific PostgreSQL pending counts were two; no projection-drift
series appeared at the sample time despite a targeted repair. This is a useful
diagnostic limitation, not evidence that the backlog or repair did not happen.
Publisher failure counters and consumer logs corroborated retries/duplicates,
while direct SQL and endpoint comparisons were the final checks.

The retained evidence was scanned for raw idempotency keys, fingerprints,
private maximums, priority sequence, secrets, credentials and sensitive headers;
no matches were found. The harness keeps new command keys only in process
memory and stores public fields, counts and event UUIDs. Remaining work:
deterministic publisher and consumer crash windows, API restart and ambiguous
retry, API-only outage, further reconciliation/worker failure integration,
adversarial review and full completion gates.
