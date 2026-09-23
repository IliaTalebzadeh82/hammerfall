# Learning guide

## Repository foundation

**Problem:** provide a reproducible starting point for two runtimes and a real
PostgreSQL database before introducing concurrent business behavior.

**Naive implementation:** generate two unrelated projects, use SQLite locally,
and defer dependency locking and executable checks.

**Why it fails:** local database behavior diverges from production PostgreSQL;
implicit runtime assumptions and stale dependencies make results hard to reproduce.

**Chosen implementation:** a small monorepo with independently locked Rails and
Next.js apps, Docker Compose for local dependencies, and the same lint/test commands
locally and in CI. The Rails application remains the future authority.

**Guarantees:** once verified, both apps boot and their foundation checks execute
against the declared runtimes. See progress.md for actual results.

**Not guaranteed:** auction correctness, concurrency safety, authentication,
production readiness, or any distributed delivery semantics.

**Read first:** README.md, docker-compose.yml, docs/adr/001-modular-monolith.md,
then docs/code-map.md.

**Tests to study:** the health request spec and the frontend starting-page test
introduced with the scaffold. They exercise the boundary that actually exists.

**Interview discussion:** why defer microservices, why test against PostgreSQL,
and why liveness differs from database readiness?

## Learning roadmap — not implemented

Add the problem, naive approach, failure modes, chosen implementation, guarantees,
limitations, source files, demonstrative tests, and interview explanation for each
subsystem when it is built:

- Bid serialization (Phase 2)
- Automatic bidding (Phase 3)
- Auction closing and soft-close (Phase 4)
- Idempotency (Phase 5)
- WebSockets (Phase 7)
- Outbox (Phase 9)
- Kafka and consumer idempotency (Phase 10)
- Redis projections (Phase 11)
- Reconciliation (Phase 12)
- Observability (Phase 13)
- Load testing (Phase 14)
- Kubernetes (Phase 18)

Do not substitute hypothetical explanations for evidence from implemented code.
