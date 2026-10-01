# Observability contract (Phase 13)

Status: Phase 13 complete after final local regression, runtime, browser,
telemetry review and hosted CI. Implementation and live evidence are tracked in the
[Phase 13 ExecPlan](plans/phase-13-execplan.md). These signals describe work;
PostgreSQL remains the sole auction authority. A missing signal never changes a
bid, closing, outbox, consumer or reconciliation decision.

## Resources and routes

Rails processes emit OpenTelemetry with service name `hammerfall-api`,
`hammerfall-sidekiq`, `hammerfall-outbox-publisher`,
`hammerfall-kafka-outbox-publisher`, `hammerfall-kafka-audit-consumer`,
`hammerfall-kafka-projection-consumer`, `hammerfall-auction-closer` or
`hammerfall-reconciliation-scheduler`, as applicable. `deployment.environment`
is a bounded value (`development`, `test`, `production`). The Collector
uses `service.instance.id` (container hostname and process PID) to keep
separate process counters distinct; dashboard queries sum across instances.
This dimension grows with process restarts, not with auctions or commands.
The Collector
receives OTLP/HTTP on the private Compose network, exports traces to Tempo and
exposes aggregated OTLP metrics for Prometheus scraping. Grafana reads
Prometheus and Tempo through provisioned data sources. Rails writes operational
JSON to stdout; no log backend or durable log retention is claimed.

Use W3C `traceparent` and `tracestate` for HTTP, Sidekiq job metadata and
Kafka headers. `baggage` is not propagated. Each asynchronous producer
finishes without waiting for its consumer; consumer spans are new work in
extracted context. Stable outbox `event_id` remains delivery/duplicate identity,
independent of trace IDs. A persisted trace carrier may be used only for public
outbox metadata; never put private bids or raw commands into it.
The outbox stores bounded trace fields outside the versioned Kafka business
envelope. Sidekiq metadata leaves job arguments unchanged. Malformed or
oversized trace metadata is ignored. A retry keeps its event UUID even when
its producer and consumer spans run later.

Span names describe operations rather than IDs: `hammerfall.auction.lock`,
`hammerfall.bid.decide`, `hammerfall.proxy.resolve`,
`hammerfall.auction.close`, `hammerfall.outbox.publish`,
`hammerfall.kafka.publish`, `hammerfall.kafka.consume`,
`hammerfall.projection.update`, `hammerfall.reconciliation.batch` and
`hammerfall.reconciliation.repair`. HTTP instrumentation should use a route
template, not an ID-bearing path. Spans may contain bounded operation, result,
error class, event type and auction status. They must not contain request
bodies, private maximum/priority, raw idempotency keys or fingerprints, Kafka
payloads, credentials, user data or arbitrary exception messages. Database
instrumentation must not record bind values. IDs needed for incident lookup
belong in access-controlled logs, not metric labels.

## Metric contract

Counters are cumulative within a process; the Collector exposes process
streams and Prometheus queries aggregate across replicas. Histograms use
seconds. Prometheus may normalize OTel names and append
`_total` or `_bucket`; verify actual exported names before writing queries.

| Signal | Unit/type | Bounded dimensions | Operational question and limit |
|---|---|---|---|
| `hammerfall_bid_requests` / `hammerfall_bid_accepted` / `hammerfall_bid_rejected` | count, counters | `operation`; rejection `reason` from a fixed enum | Did commands arrive and what outcome did they receive? A replay is a historical response, not another accepted bid. |
| `hammerfall_bid_processing_duration` | seconds, histogram | `operation`, `result` | How long did command processing take? Includes queueing/DB work; does not isolate lock wait. |
| `hammerfall_auction_lock_wait_duration` | seconds, histogram | `operation` | How much time passed during PostgreSQL auction row lock acquisition? Includes reload/query time. |
| `hammerfall_auction_extensions` | count, counter | none | How often did an accepted action extend a deadline? |
| `hammerfall_auction_close_lag` | seconds, histogram | none | How late was a successful DB-clock close relative to `ends_at`? Polling is not an SLA. |
| `hammerfall_outbox_pending_events` / `hammerfall_outbox_oldest_event_age` | count gauge / seconds gauge | `channel=sidekiq|kafka` | Is committed publication intent backing up? Acknowledgment means queue enqueue or broker delivery, not browser receipt or consumer effect. |
| `hammerfall_outbox_publish_attempts` / `hammerfall_outbox_retry_attempts` / `hammerfall_outbox_publish_failures` / `hammerfall_outbox_publish_duration` | count counters / seconds histogram | `channel` | Are external deliveries slow/retrying while a DB lock is held? Duration surrounds transport delivery, not the whole transaction. |
| `hammerfall_sidekiq_queue_depth` / `hammerfall_sidekiq_jobs` / `hammerfall_sidekiq_job_duration` | gauge / counter / seconds histogram | queue, bounded result | Are notification jobs queued or failing in workers? Enqueue is not Cable delivery. |
| `hammerfall_kafka_consumed` / `hammerfall_projection_writes` | count counters | group and bounded result | Did a consumer commit a first/next/gap/stale/duplicate arrival, or a Redis write apply/duplicate/stale/conflict/fail? |
| `hammerfall_kafka_consumer_lag` | count gauge | `consumer_group`, `partition` | Is a named consumer behind the broker? Partition is bounded by topic configuration. Broker position does not prove effect completion. |
| `hammerfall_projection_checks` / `hammerfall_projection_drift` / `hammerfall_projection_repair_attempts` / `hammerfall_projection_repairs` / `hammerfall_projection_repair_failures` / `hammerfall_projection_operator_review` | count, counters | drift `kind=missing|behind|conflict|corrupt|ahead|unavailable` where applicable | Are projections drifting and can safe repairs complete? None of these counters change PostgreSQL truth. |
| `hammerfall_projection_stale_age` | seconds, histogram | `source` from fixed enum | How old was an observed projection? It measures a check, not a freshness guarantee. |
| `hammerfall_projection_batch_size` / `hammerfall_projection_scan_duration` | count / seconds histograms | none | How much reconciliation work was checked in each page and how long did it take? |
| `hammerfall_websocket_broadcasts` / `hammerfall_websocket_server_broadcast_lag` | counter / seconds histogram | bounded `result` | Did the server issue a Cable broadcast and how long after event occurrence? This cannot prove browser receipt. |
| `hammerfall_http_requests` / `hammerfall_http_duration` | count counter / seconds histogram | route template, method, status class | Is the API healthy? Never label a raw URL. |

Default duration histogram boundaries should span milliseconds through tens of
seconds (`0.001`, `0.005`, `0.01`, `0.025`, `0.05`, `0.1`, `0.25`, `0.5`,
`1`, `2.5`, `5`, `10`, `30` seconds). Lock wait and publication share these
for useful tail comparisons. Count/age gauges have no histogram boundaries.
Final names, units and dashboard queries were checked against live Prometheus
series; the [operations runbook](runbooks/observability.md) explains how to
diagnose missing or stale signals.

No metric label may contain an auction, user, bidder, bid, event, trace or span
ID; idempotency key; raw error message; email; or URL with arbitrary IDs.
`reason` must map to a fixed code set with an `other` fallback. Component,
operation, status class and Kafka group are fixed allowlists.
Partition labels accept only 0–31; projection drift kinds are a finite enum.

## Logs and correlation

Operational boundary logs are one JSON object per line with `timestamp`,
`level`, `service`, `operation`, `component`, `result`, and optional
`error_class`, `auction_status`, `event_type`, `consumer_group`, `partition`,
`retry_count`, `public_revision`, `auction_id`, `event_id`, `trace_id`,
`span_id`. Trace and span IDs are present only when a valid active context
exists. Auction/event IDs are allowed only where they materially help incident
diagnosis; log storage access must be controlled. Do not log whole Rails params,
Kafka payloads, exception messages, raw keys or credentials. Generic framework
logs may remain in their existing format during this phase.
Development Rails logs use info level because debug SQL inlined private maximum
and priority values. Rails filters whole auction, bid, maximum-bid and user
request payloads before its request log. Structured async logs
include event IDs only for protected operational lookup.

## Sampling and failure behavior

Local development samples all traces to make flow inspection possible.
Production sampling is a bounded, explicit ratio; sampling never determines
whether a metric or business operation occurs. SDK span queues/batches and
collector memory/queues must be finite. Export timeout and failed collection
may drop telemetry. Application startup and request/worker paths must remain
usable when Collector, Prometheus, Tempo or Grafana are down. Observability
exceptions are contained at the telemetry boundary, while domain, PostgreSQL
and transport exceptions retain their existing behavior. No telemetry service
appears in an application `depends_on` health gate.
The Ruby span queue holds at most 1,024 spans and drops the oldest on overflow;
batches hold at most 256 and export once per second with a one-second timeout.
The metric reader exports every 15 seconds with a one-second timeout and a
200-series cardinality cap per instrument/reader. The Collector has a 128 MiB
memory limiter and a 100-batch trace queue with at most 30 seconds of retries.
Ruby exporter retries run in SDK export threads. A 30-second Collector outage
produced export errors while four proxy bidding smokes passed and both outbox
backlogs drained; this is bounded local evidence, not a capacity claim.

The Compose stack and local dashboards are development examples, not hardened
public endpoints. Bind browser-facing Grafana to loopback and keep Collector,
Prometheus and Tempo inside the Compose network. Local Grafana has anonymous
Viewer access with initial admin creation disabled, so no default password is
committed. This mode must not be exposed on a public network.

## Local inspection

Set `OTEL_ENABLED=true` for the application processes and start the optional
stack with `docker compose --profile observability up -d --build`. The
provisioned Grafana UI is at `http://127.0.0.1:3002` by default; data sources
and the question-driven Hammerfall operations dashboard are ready. Normal
Compose startup leaves OTel disabled. The Collector, Prometheus and Tempo have
no host port mapping. Use `docker compose --profile observability ps` and
Prometheus target health before interpreting an empty dashboard. Trace export
uses OTLP/HTTP `/v1/traces`; metric export uses `/v1/metrics`.

Prometheus appends `_total` to counters and `_seconds` to duration instruments;
count gauges retain their base name. Backlog dashboards use `max` across
publisher replicas because each publisher reads the same global PostgreSQL
backlog. Kafka lag is a broker high-watermark sample after a successful offset
commit, at most once per partition every 30 seconds when messages arrive. An
idle or stopped consumer does not refresh it; inspect broker group offsets
before concluding a group has caught up. Projection and broadcast metrics
describe derived delivery only.
