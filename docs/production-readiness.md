# Production readiness

This is a development system with tested concurrent manual bidding, not a
production auction service. PostgreSQL serializes each auction's writers; a hot
auction can queue requests and exhaust connection capacity. No load measurement
or throughput claim exists. Long outer transactions retain locks longer.

There is no distributed closing/time protocol, authentication, authorization,
idempotency, rate limiting, backup/restore procedure, production deployment or
operational runbook. Reads spanning multiple queries are not snapshot-consistent.
Local Compose credentials are disposable; services bind to loopback. Named volumes
provide local persistence, not backups. The sequence migration requires stopping
old writers for a maintenance rollout, not an untested rolling deployment.

Before real-money use, implement and test remaining invariants/failure scenarios,
review security, verify durable backup restores, measure capacity and assign
operational ownership. See progress.md and ADR-003 for actual evidence and limits.
