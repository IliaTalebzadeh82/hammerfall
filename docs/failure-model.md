# Failure model

## Current foundation

| Failure | Current effect | Recovery |
| --- | --- | --- |
| PostgreSQL unavailable | Database operations/tests fail; `/up` may still return 200 | Restore PostgreSQL, then retry startup/database checks |
| Rails unavailable | `/up` fails; static frontend can still load | Restart API and inspect logs |
| Next.js unavailable | Starting page unavailable | Restart frontend and inspect logs |
| Dependency registry unavailable | First install/build or startup install can fail | Restore registry access and retry; lockfiles remain authoritative |

Phase 1 now persists business data. Bid insertion and current-price update either
commit together or roll back. If a response is lost after commit, clients cannot
safely deduplicate a retry yet. Application restart does not erase PostgreSQL data;
a local volume is not a backup. Ended auctions need an explicit close action.
Concurrent bid/close behavior remains unproven and unsafe. No failover or
availability promise is made. Later phases must document Redis/Kafka outages, worker/consumer
crashes, dropped WebSockets, publication delays, duplicate events, latency spikes,
and delayed/concurrent closing workers using the master specification's questions:
what remains correct, unavailable or stale, and how recovery happens.
