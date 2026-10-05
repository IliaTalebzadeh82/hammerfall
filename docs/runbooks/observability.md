# Observability runbook

PostgreSQL and the Rails domain decide auction outcomes. The optional local
Collector, Prometheus, Tempo and Grafana stack observes those outcomes. A blank
panel or absent trace is missing evidence, not proof that no work occurred.
See the [signal contract](../observability.md) for exact metric units, bounded
labels and the limits of each signal.

## Check the pipeline

```sh
docker compose --profile observability ps
docker compose logs --tail 100 --no-color otel-collector prometheus tempo grafana
docker compose exec -T api bin/rails runner 'puts Observability.enabled?'
```

Check the Collector targets in Prometheus before interpreting Grafana. A
healthy Grafana process does not prove fresh data. If `OTEL_ENABLED=false`,
application signals are intentionally absent. The Collector and storage peers
are not application health dependencies; a telemetry outage can drop spans or
metric exports while bidding, publishing and reconciliation continue.

For a bid incident, read the authoritative API response and PostgreSQL state
first. Use the trace to locate time in the command, auction lock, outbox and
asynchronous paths. A Sidekiq enqueue does not prove Cable broadcast or browser
receipt. A Kafka broker acknowledgment does not prove consumer completion.
Consumers may retry the same event under new spans while the event UUID and
authoritative effect stay stable.

## Interpret backlog and lag

- Compare bid processing duration with auction lock wait to investigate hot
  rows. The difference is not an exact decomposition of CPU versus database
  work.
- Publisher duration surrounds external delivery while a PostgreSQL outbox
  row lock is held. Inspect backlog and oldest age for each channel before
  changing publisher counts. The backlog gauges are global database reads;
  aggregate publisher replicas with `max`.
- Kafka lag is sampled only after successful offset commits on active
  consumers. An idle or dead consumer can leave a stale gauge. Confirm the
  broker group offsets using the [Kafka runbook](kafka.md).
- Reconciliation counters are cumulative process metrics. Structured `_batch`
  log fields are per-batch deltas. Redis is derived; use ordinary PostgreSQL
  backed GET and the [reconciliation runbook](projection-reconciliation.md)
  when a projection differs.
- WebSocket lag ends at the server broadcast. Confirm the browser's current
  state through a fresh REST GET.

## Export outage and recovery

The Ruby SDK uses a 1,024-span queue, 256-span batches, one-second export
timeout and 15-second metric export interval. Its metric cardinality limit is
200 series per instrument/reader. The Collector applies a 128 MiB memory
limit, a 100-batch trace queue and at most 30 seconds of retries. Prolonged
outages may drop telemetry. Export attempts run outside auction decisions;
there is no zero-overhead or lossless-export guarantee.

Restore the failed telemetry peer, confirm Collector scrape targets and query
new Prometheus samples and a new Tempo trace. Do not treat a restored dashboard
as recovery of data dropped during the outage. Session 2 local outage evidence
is indexed in the [Phase 13 ExecPlan](../plans/phase-13-execplan.md); it is not a
capacity or queue-saturation benchmark.

Structured boundary logs carry bounded operation/result fields and, when
sampled, trace/span IDs. Control access to logs containing auction/event IDs.
Do not copy raw commands, private maximums, Kafka payloads or credentials into
incident reports.

## Phase 22 alert response

The provisioned Prometheus evaluates four local rules every 15 seconds.
Thresholds and durations are provisional detection settings; production SLOs
are unset. [The final operations report](../operations/phase-22-final.md)
records the rationale, limits and incident severity policy. Verify the series
is fresh and the relevant process is running before interpreting a clear rule.

| Alert | Signal, threshold, duration | Severity / owner / impact / response |
| --- | --- | --- |
| `OutboxBacklogOld` | Maximum oldest pending age by channel >90 seconds for two minutes | SEV-3, async operator. Public hints or Kafka events are delayed. Check publisher health and both backlog channels; follow [Sidekiq](sidekiq-redis.md) or [Kafka](kafka.md). Escalate if authority is affected. |
| `ProjectionOperatorReview` | Any increase in operator-review counter over five minutes, sustained one minute | SEV-3, async operator. Redis public state may disagree with PostgreSQL; inspect the affected auction and [reconciliation runbook](projection-reconciliation.md). Do not erase an ahead key before timeline review. |
| `MutationServerErrorsHigh` | At least five auction POST/PUT/PATCH 5xx responses in five minutes, sustained one minute | SEV-2, API operator. User commands may fail. Check API, PostgreSQL and dependencies; establish whether any command committed before retrying with the same key. Valid 4xx rejections do not count. |
| `AuctionCloseLagHigh` | At least one successful close >10 seconds after authoritative deadline in ten minutes, sustained one minute | SEV-2, auction operator. Inspect closer process, PostgreSQL pressure and due auctions. The histogram cannot detect a completely stopped closer; verify process health and query due active auctions. |

Each alert points to this or its specific runbook. The local setup has no
pager/Alertmanager routing or staffed on-call rotation; Prometheus rule state
is the observed alert behavior. Do not treat absent/stale telemetry as healthy
service. Kafka lag gauge updates only on successful commits, so inspect broker
group offsets before diagnosing a stopped or idle consumer.

The Phase 22 isolated game day observed `OutboxBacklogOld` inactive at a zero
Kafka age, pending after the real broker outage, firing at 216 seconds, then
inactive at zero after fresh-broker replay. A stopped publisher's last gauge
can persist in the Collector until metric expiration; confirm process health
and series identity before interpreting clear/firing. The disposable game-day
Collector used a one-minute expiration; ordinary configuration was unchanged.
