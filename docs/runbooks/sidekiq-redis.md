# Phase 8 job and Redis runbook

This is a development/operations guide for the public notification and read-only sweep jobs. PostgreSQL auction state is authoritative. `auction.changed.v1` is a best-effort hint, not a domain event or a command result.

## Inspect

```sh
docker compose ps api db redis sidekiq reconciliation-scheduler auction-closer
docker compose exec -T redis redis-cli ping
docker compose logs --tail 100 --no-color sidekiq reconciliation-scheduler api redis
docker compose exec -T api bin/rails runner 'require "sidekiq/api"; puts({ notifications: Sidekiq::Queue.new("notifications").size, maintenance: Sidekiq::Queue.new("maintenance").size, retries: Sidekiq::RetrySet.new.size, dead: Sidekiq::DeadSet.new.size }.inspect)'
```

Do not paste logs containing client requests or private data into tickets. The notification job payload should contain only auction ID and revision. A queue length of zero does not prove no hint was lost before enqueue.

## Worker stopped or backlog growing

Symptom: notification queue grows, browser updates arrive late; REST reads and bidding still work. Check Redis `PONG`, worker process/restart logs and job failures. Restart a stopped worker with `docker compose start sidekiq`, then observe queue drain and successful `AuctionChangedJob` logs. A delayed job reads current revision and broadcasts a fresh hint, so duplicate/reordered execution is safe. Verify current state through REST; do not infer bid success from queue delivery.

## Redis unavailable or data lost

Symptom: API logs `auction_notification enqueue_failed` and scheduler logs `enqueue_failed`; Sidekiq cannot process. Bidding, idempotent replay and closing must still use PostgreSQL. Restore Redis, confirm `PONG`, worker connection and a one-shot sweep (`docker compose exec -T reconciliation-scheduler bin/reconciliation_scheduler --once`). Existing queued work may drain; **missed enqueue attempts are not reconstructed**. A connected browser can remain stale until manual/focus/command/countdown/reconnect recovery. Do not claim that starting Redis repairs the commit-to-enqueue gap.

Local Redis uses a named volume with append-only persistence. This is no backup or exactly-once guarantee. Do not delete the volume as a routine recovery step. In production, decide persistence, backup, network isolation and high availability before relying on the queue.

## Retries, dead jobs and drift

Jobs retry at most five times and then enter Sidekiq's Dead set. Inspect the job class, public numeric args and error class; restore the failing dependency before retrying an individual job through the Sidekiq API/console. Do not mount an unauthenticated Sidekiq Web UI on the public app. Deleting a failed notification forfeits the hint, but does not undo the committed auction. If a job has a future revision relative to PostgreSQL, investigate schema rollback/data corruption before retrying.

The scheduler is not an exact cadence or singleton guarantee. Its `--once` command exits nonzero on Redis enqueue failure. The sweep reads bounded PostgreSQL batches and logs `auction_reconciliation drift auction_id=… kind=postgresql_state`; it never repairs data. Investigate the auction and latest accepted Bid under a consistent read, preserve evidence and plan a deliberate repair. Repeated or duplicate sweep logs are possible. Phase 12 will define Redis projection comparison and safe repair.
