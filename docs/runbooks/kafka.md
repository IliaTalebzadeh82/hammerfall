# Kafka domain-event runbook

Phase 10 local Kafka propagates public domain snapshots from committed
PostgreSQL outbox rows. PostgreSQL alone decides bids, prices, deadlines,
winners and command outcomes. Kafka failure does not require stopping bidding.
The Sidekiq/Cable invalidation path is independent. See [ADR-011](../adr/011-kafka-domain-events.md)
and the [event model](../event-model.md).

## Inspect the pipeline

From the repository root:

```sh
docker compose ps db kafka kafka-outbox-publisher kafka-audit-consumer outbox-publisher sidekiq
docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:9092 --describe --topic hammerfall.auction-events.v1
docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 --describe --group hammerfall.audit.v1
docker compose logs --tail=100 --no-color kafka-outbox-publisher kafka-audit-consumer
docker compose exec -T api bin/rails runner 'puts({ pending: OutboxEvent.kafka_pending.count, due: OutboxEvent.kafka_due.count, retrying: OutboxEvent.kafka_pending.where("kafka_attempts > 0").count }.inspect)'
```

The publisher logs aggregate backlog, due, retries and oldest age each cycle.
Its row errors record only class names. Inspect a specific row's event ID,
revision, attempts and next attempt time in a protected Rails console; do not
log raw payloads or private records. A `kafka_published_at` value means broker
delivery was confirmed. It says nothing about consumer completion.

## Broker unavailable or slow

The publisher leaves rows pending with exponential retry capped at 300 seconds.
Confirm PostgreSQL bidding and the Sidekiq path separately; restore the broker
with `docker compose start kafka` if it was stopped. Check topic metadata,
publisher backlog and consumer-group lag. A controlled one-shot drain is
`docker compose exec -T kafka-outbox-publisher bin/kafka_outbox_publisher --once`;
it exits nonzero when a due delivery fails. Wait for persisted backoff before
repeating. Do not set `kafka_published_at` manually or delete a pending row to
clear backlog. The local broker has one replica and a named volume, not a
backup or production availability design.

## Publisher or consumer crash

Publisher death before database acknowledgment leaves the row pending even if
Kafka accepted it. Restart the publisher and expect possible duplicate event
IDs. The audit receipt makes duplicate side effects no-ops. Multiple publisher
instances may reorder revisions, even though a given auction key uses one Kafka
partition. Audit rows classify first, next, gap and stale arrivals. Investigate
persisting gaps; they may indicate missing or delayed publication.

The audit consumer group commits offsets only after its PostgreSQL receipt and
audit entry commit. If it dies after that database commit, `docker compose start
kafka-audit-consumer` replays a duplicate without another effect. If the
database effect failed, the offset remains pending and the record is retried.
The consumer has no automatic container restart policy so poison records do not
create a restart loop. Check the group's lag after restart.

## Poison records and explicit recovery

An unknown version/type, malformed shape, wrong key, oversized payload or
conflicting reuse of an event ID stops the consumer without committing the
record. Logs contain partition, offset and error class, not the payload.
Later records in that partition wait. Review the exact record in a protected
environment, determine whether the publisher or event contract needs repair,
and preserve evidence. Never skip a valid event merely to reduce lag.

For a deliberate skip after review, keep the group stopped and reset **only**
the affected partition to the next offset. Replace `1` and `8` with the
observed partition and poison offset + 1. First omit `--execute` to preview:

```sh
docker compose stop kafka-audit-consumer
docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 --group hammerfall.audit.v1 --topic hammerfall.auction-events.v1:1 --reset-offsets --to-offset 8
docker compose exec -T kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server kafka:9092 --group hammerfall.audit.v1 --topic hammerfall.auction-events.v1:1 --reset-offsets --to-offset 8 --execute
docker compose start kafka-audit-consumer
```

Verify the group offset and audit/receipt count after restart. The skipped
record is intentionally unprocessed for this group; record the decision and
reason. Replaying earlier retained offsets is also possible by resetting the
stopped group to an earlier offset. Receipts suppress repeat effects, but replay
encounters an unresolved poison record again. Broker retention bounds replay;
the Phase 9 historical rows were not backfilled as domain events.

## Limits

The local topic has three partitions and replication factor one. There is no
TLS/authentication, multi-broker durability, external schema registry, alerting,
capacity evidence, fixed delivery deadline or exactly-once guarantee. A
consumer receipt protects only its own PostgreSQL effect; future consumers
need separate group identities, receipts, schemas and replay policy. Phase 11's
separate `hammerfall.projection.v1` group writes a disposable Redis public
snapshot; inspect and recover it using the [projection runbook](redis-projection.md).
The browser continues to use REST plus Sidekiq/Cable hints, never Kafka offsets.
