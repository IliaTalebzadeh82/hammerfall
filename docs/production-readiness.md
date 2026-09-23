# Production readiness

This is a sequential auction domain and development foundation, not a production auction system.

There is no concurrent bid serialization, race-safe closure, authentication, authorization, rate limiting,
backup/restore procedure, deployment configuration, capacity measurement, or
operational runbook. Local Compose credentials are disposable development values;
Compose is bound to loopback. Named volumes provide local persistence, not backups.

Before real-money use, all domain invariants and failure scenarios need tested
implementations, security review, durable backups with restore verification,
measured capacity, operational ownership, and a separate production deployment plan.
