# Public outbox, Sidekiq and Redis runbook

This is a development/operations guide for the Phase 9 outbox, public notification and read-only sweep jobs. PostgreSQL auction state is authoritative. `auction.changed.v1` is a public hint, not a command result.

## Inspect

```sh
docker compose ps api db redis sidekiq outbox-publisher reconciliation-scheduler auction-closer
docker compose exec -T redis redis-cli ping
docker compose logs --tail 100 --no-color outbox-publisher sidekiq reconciliation-scheduler api redis
docker compose exec -T api bin/rails runner 'p OutboxPublisher.new.backlog_metrics'
docker compose exec -T api bin/rails runner 'require "sidekiq/api"; puts({ notifications: Sidekiq::Queue.new("notifications").size, maintenance: Sidekiq::Queue.new("maintenance").size, retries: Sidekiq::RetrySet.new.size, dead: Sidekiq::DeadSet.new.size }.inspect)'
```

Do not paste logs containing client requests or private data into tickets. The notification job payload should contain only auction ID and revision. Check pending/due/retry counts and oldest age alongside queue depth; a zero queue alone does not prove all committed intents were enqueued.

## Worker stopped or backlog growing

Symptom: notification queue grows, browser updates arrive late; REST reads and bidding still work. Check Redis `PONG`, worker process/restart logs and job failures. Restart a stopped worker with `docker compose start sidekiq`, then observe queue drain and successful `AuctionChangedJob` logs. A delayed job reads current revision and broadcasts a fresh hint, so duplicate/reordered execution is safe. Verify current state through REST; do not infer bid success from queue delivery.

## Redis unavailable or data lost

Symptom: publisher logs `outbox_publisher enqueue_failed` and scheduler logs `enqueue_failed`; Sidekiq cannot process. Bidding, idempotent replay and closing still use PostgreSQL. Pending outbox rows survive. Restore Redis, confirm `PONG`, then confirm `outbox-publisher` and worker are running. Run `docker compose exec -T api bin/outbox_publisher --once` if a controlled drain is needed; a failed attempt exits nonzero and persists backoff, so wait for due time before retrying. Check backlog/due/retry/oldest-age values and completed `AuctionChangedJob` logs. Run a one-shot sweep separately (`docker compose exec -T reconciliation-scheduler bin/reconciliation_scheduler --once`). A connected browser may still need manual/focus/command/countdown/reconnect REST recovery.

Local Redis uses a named volume with append-only persistence. This is no backup or exactly-once guarantee. Do not delete the volume as a routine recovery step. In production, decide persistence, backup, network isolation and high availability before relying on the queue.

## Retries, dead jobs and drift

Outbox enqueue retries are indefinite, with exponential backoff capped at 300 seconds. Repeated `last_error` classes, retry count, backlog and oldest age need operator investigation. The outbox row is never silently deleted. Do not force `published_at` or remove a poisoned row to clear a dashboard. Sidekiq jobs retry at most five times and then enter the Dead set. Inspect the job class, public numeric args and error class; restore the failing dependency before retrying an individual job through the Sidekiq API/console. Do not mount an unauthenticated Sidekiq Web UI on the public app. Deleting a failed notification after enqueue can forfeit the hint, but cannot undo the committed auction. If a job has a future revision relative to PostgreSQL, investigate schema rollback/data corruption before retrying.

An outbox acknowledgment means Sidekiq accepted the job, not that Cable delivered it. Redis data loss after acknowledgment and exhausted job retries are outside outbox recovery. Multiple publishers may process rows out of order; duplicate jobs are safe because they read current revision. Use a current REST GET to verify auction truth. The publisher's Redis network timeout is two seconds; long database stalls and high backlog can still delay delivery without a fixed bound.

The scheduler is not an exact cadence or singleton guarantee. Its `--once` command exits nonzero on Redis enqueue failure. The sweep reads bounded PostgreSQL batches and logs `auction_reconciliation drift auction_id=… kind=postgresql_state`; it never repairs data. Investigate the auction and latest accepted Bid under a consistent read, preserve evidence and plan a deliberate repair. Repeated or duplicate sweep logs are possible. Phase 12 will define Redis projection comparison and safe repair.
