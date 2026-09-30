# ADR-013: Bounded scheduled reconciliation scan ownership

Status: Accepted — Phase 12, 2026-10-01

## Context

The Phase 8 read-only PostgreSQL sweep and Phase 12 Redis projection scan each
process at most 100 auctions per job and enqueue their next page. The periodic
scheduler previously started a fresh chain on every tick. If a full scan took
longer than the tick interval, chains could accumulate without bound. Redis
revision checks keep repairs safe but do not bound duplicate queue or database
work. Multiple scheduler processes amplify the problem.

## Decision

PostgreSQL stores one short-lived lease for each scheduled scan type:
`postgresql_state` and `projection`. The scheduler atomically claims an absent
or expired lease using PostgreSQL `clock_timestamp()`, then enqueues the first
page with a random owner token. Other schedulers skip that type while its lease
is live. The two scan types remain independent.

Each scheduled page confirms and renews its token before work, periodically
within a page, and atomically advances the lease cursor before enqueueing its
successor. Only one attempt for a given cursor can advance it, so a Sidekiq
retry after successor enqueue cannot branch a scan chain. A page that has lost
ownership or whose cursor was already advanced stops; the next owner starts at
the beginning, so no rows are skipped.
The final page conditionally deletes its own lease. A crashed scheduler after
claim, lost queue entry, worker crash or failed continuation leaves an expiring
lease; a later tick can claim it and restart the scan. The lease is ten minutes
and renewed every 25 rows plus page boundaries. A stalled page can finish at
most bounded work after ownership changes; fencing prevents it from extending
an old chain. A new owner never waits on an auction row lock.

If a worker crashes after cursor advancement but before successor enqueue,
the lease eventually expires and a later scheduler restarts from ID zero.
Repeated work is safe through the projection revision guard and the read-only
PostgreSQL sweep. No exactly-once queue handoff is claimed.

No transaction or database connection is held across a scan chain. A manual
job invocation without a token is explicitly independent of scheduled
ownership and may overlap; its bounded/idempotent semantics remain. The lease
coordinates maintenance load only. PostgreSQL auction state is still the only
authority; missing ticks or lease failures affect detection latency, never bid
legality, price, deadline or winner.

## Alternatives

- A process-local flag cannot coordinate multiple schedulers or survive a
  crash.
- A PostgreSQL advisory lock held for the whole chain would pin a connection
  across Sidekiq jobs and process boundaries. A transaction-long lock would
  also hold database resources during Redis I/O.
- Redis queue uniqueness or a Redis lease would couple maintenance ownership
  to the disposable projection/job transport and does not provide the needed
  database-clock fencing after ambiguous enqueue or worker failure.
- An unbounded duplicate chain policy leaves the discovered operational issue
  unresolved even though individual repairs are safe.

## Consequences and limits

An outage of PostgreSQL prevents new claims and page renewals; the scheduler
logs and retries later. An expired owner may finish part of one 100-row page
while the replacement starts, but it cannot continue to another page. A slow
or blocked page can lose its lease; work restarts from ID zero after a later
tick. The ten-minute expiry bounds abandoned ownership but does not guarantee
a maximum convergence time. Manual scans are operator actions and are not
deduplicated against scheduled scans. The read-only PostgreSQL sweep retains
its reporting semantics; only its scheduled overlap is bounded.
