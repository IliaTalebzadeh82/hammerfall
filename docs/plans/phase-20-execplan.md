# Phase 20 ExecPlan — Identity & Security

Status: Active Phase 20; Sessions 1 and 2 checkpointed. Phase 20 is not complete; Phase 21 has not started.
Current milestone: Session 2 security control architecture and focused live proof complete; Session 3 final gate remains.
Completed: Session 1 identity foundation (below); Session 2 real Next rewrite cookie/CSRF/Cable and two-replica identity/replay proof; Redis-backed endpoint-class rate limits with explicit outage policy; 32 KiB early body bound; versioned HMAC idempotency digests with legacy/rotation lookup; bounded security events; post-handshake Cable public-hint policy; narrowed public user listing; Compose development secret sharing. See [Session 2 report](../security/phase-20-session-2.md).
Verified: Session 1 evidence below; Session 2 focused PostgreSQL specs, live A/B and browser/Redis-outage/body proofs, frontend suite/build, Ruby/TS lint, Brakeman, advisory audit and Zeitwerk (Evidence Index). Final backend full-suite result is recorded below.
Remaining: Session 3 must adapt legacy smoke/Playwright clients; run full Compose/browser/hosted CI gates and final multi-instance regression; reconcile final docs/progress and declare Phase 20 complete only after those pass.
Known failures/limitations: Legacy `scripts/smoke-*` and Playwright clients still use removed user creation/actor selection. Established Cable sockets may continue receiving public hints after revocation until disconnect. Local fallback limiter quota during Redis outage is per process. GKE Gateway body buffering and live cloud secret distribution are unverified; Terraform binary was unavailable locally. No paid cloud work.
Relevant files: `apps/api/app/controllers/api/v1/`, `app/services/rate_limit_store.rb`, `app/services/idempotency/`, `lib/request_body_limit.rb`, `app/channels/`, `apps/web/src/lib/api/client.ts`, `docker-compose.yml`, cloud overlay and Terraform secret metadata.
Relevant ADRs: [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md), [ADR-006](../adr/006-client-command-idempotency.md), [ADR-007](../adr/007-browser-command-intentions.md).
Next-session starting point: Read this plan, [the Session 2 report](../security/phase-20-session-2.md), [latest handoff](../handoffs/latest.md) and [Phase 20 spec](../phases/phase-20.md). Adapt legacy transport clients, then run Session 3 final gates. Use isolated Redis DB 15 and `RAILS_MAX_THREADS=15` for ten-worker concurrency specs. Do not start Phase 21.

## Decisions

- ADOPT: PostgreSQL-backed opaque sessions, bcrypt credentials, cookie transport, same-origin CSRF header; see ADR-016.
- ADOPT: Preserve existing `actor_id` and fingerprint semantics with server-derived identity; authenticate before idempotency lookup.
- ADOPT: Public auction reads, owner draft management/cancel, operator schedule/activate/close; internal closer remains independent.
- REJECT: JWT and browser-readable bearer storage for the current same-origin client.
- ADOPT: Rails-native endpoint rate limits backed by a shared Redis store; login and Cable fail closed during Redis loss, while bid/lifecycle admission uses a half-quota process-local fallback. PostgreSQL remains auction authority.
- ADOPT: Early Rack and local Nginx 32 KiB body guards; 413 is a definite pre-command rejection.
- ADOPT: Versioned HMAC digests, legacy SHA lookup and a transaction advisory lock for logical-key ownership. Drain old executors before new writes; keep all key IDs until their rows are physically pruned. See ADR-017.
- ADOPT: Existing Cable sockets can receive only public hints after logout/expiry; new handshakes/subscriptions check live session. Narrow public users to bidders with public bids.
- REJECT: Process-local cache as the normal distributed limiter and blind fail-open login on Redis loss.
- DEFER: Legacy smoke/Playwright migration and full hosted/Compose final gate to Session 3.
- NEEDS EVIDENCE: GKE Gateway prebuffer request size and live cloud secret rollout; no cloud apply authorized or performed. Session 3 should validate static Terraform when a binary is available.

## Work tracks

Session 1 touched migration/schema/User/UserSession, session/auction/bid controllers, policy, locked auction self-bid, Cable, frontend session/client, tests and contract/docs. Session 2: rate limits and Redis failure policy; request-body limits at edge and app; HMAC legacy lookup, shared secret and key rotation; structured events; multi-instance behavior. Session 3: adapt smoke/Playwright, regression, audits, startup, hosted CI, docs and final review.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Current trust inventory | Targeted routes/controllers/models/frontend review | Completed | [Session 1 report](../security/phase-20-session-1.md) |
| Official guidance | Rails security/API/Cable and OWASP session/CSRF/JWT docs | Completed | ADR-016 source links |
| Focused identity/Cable/models | `bundle exec rspec` selected user/session/identity/Cable/seed specs | 34 examples, 0 failures; seed 5919 | `/tmp/phase20-auth-final.log` |
| Final owner check | `bundle exec rspec spec/requests/identity_security_spec.rb spec/models/auction_spec.rb` | 70 examples, 0 failures; seed 10821 | `/tmp/phase20-owner-final.log` |
| Checkpoint seed/identity/owner regression | `REDIS_URL=redis://127.0.0.1:6379/15 bundle exec rspec spec/integration/seeds_spec.rb spec/requests/identity_security_spec.rb spec/models/auction_spec.rb` | 73 examples, 0 failures; seed 47073 | `/tmp/phase20-checkpoint-focused.log` |
| Request regression | `REDIS_URL=redis://127.0.0.1:6379/15 bundle exec rspec` selected request/seed specs | 79 examples, 0 failures | `/tmp/phase20-request-focused.log` |
| Backend regression | `REDIS_URL=redis://127.0.0.1:6379/15 bundle exec rspec` | 470 examples, 0 failures, 3 existing gated Kafka pending; seed 13658 | `/tmp/phase20-backend-isolated.log` |
| Redis isolation diagnosis | Initial full suite on development Redis DB 0 | 468 examples, 16 projection/reconciliation failures caused by stale keys colliding with reused test IDs; isolated DB 15 rerun passed | `/tmp/phase20-backend-suite.log`, isolated rerun above |
| Frontend | `npm run typecheck && npm run lint && npm run format:check && npm test -- --reporter=dot && npm run build` | All passed; 75 tests, 0 failures; Next production build passed | Command output |
| Ruby lint/load | `bundle exec rubocop`, `bundle exec rails zeitwerk:check` | 146 files, 0 offenses; eager load passed | Command output |
| Security static/audit | `bundle exec brakeman -q -w2`; `bundle exec bundler-audit check --update` | 0 Brakeman warnings; 0 known gem advisories | Command output; advisory DB 2026-10-02 |
| Compose/browser/hosted CI | Pending Session 3 | Unrun for new contract | Legacy clients require adaptation |
| Session 2 browser rewrite | Chrome/Playwright via `http://localhost:3000` and Next rewrite | Anonymous bid 401; login 201; cross-replica session 200; CSRF bid 201; Cable welcome/subscribed; logout 204; subsequent session 401 and reconnect rejected | [Session 2 report](../security/phase-20-session-2.md) |
| Two-replica identity/replay | Direct A/B script `/tmp/phase20_replicas.cjs` | Login A; session B same actor; bid A 201; same-key replay B 201 same bid ID; logout B; session A 401 | Local Compose, Session 2 report |
| Shared limiter | Alternating direct replica wrong-login requests | Ten 401 then eleventh 429 across A/B; Retry-After 60 | Session 2 report |
| Limiter outage | Temporary Puma port 3010 with invalid Redis URL | Login 503; existing session 200; bid 201 under local fallback | Session 2 report |
| Body guard | Nginx, Next rewrite and chunked direct Rails 33,000-byte POST; Rack/request specs | 413 JSON before Rails parse; no mutation | Session 2 report |
| Cable post-logout | `/tmp/phase20_cable_expiry.cjs` Chrome socket and publication | Existing socket received only public type/auction ID/revision hint; reconnect rejected | Session 2 report and ADR-016 |
| Key rotation/concurrency | `spec/integration/idempotency_key_rotation_spec.rb`, `spec/integration/concurrent_idempotency_spec.rb` | Legacy/current/previous replay, actor/conflict/retirement; 13 concurrency examples passed with pool 15 | `/tmp/phase20-session2-concurrency.log` |
| Focused security regression | Requests auctions/rate limits and event spec | 32 examples, 0 failures; seed 1061 | `/tmp/phase20-session2-final-focused.log` |
| Session replacement/CSRF | `spec/requests/identity_security_spec.rb` after added replacement assertion | 10 examples, 0 failures; seed 30810; second login changes cookie and deletes prior row | `/tmp/phase20-session2-session-replacement.log` |
| Session 2 backend full regression | `REDIS_URL=redis://127.0.0.1:6379/15 RAILS_MAX_THREADS=15 OTEL_ENABLED=false bundle exec rspec` | 493 examples, 0 failures, 4 pending; seed 4494 | `/tmp/phase20-session2-backend-final.log` |
| Session 2 frontend | `npm test -- --reporter=dot`; types/lint/format/build | 76 tests, 0 failures; all static/build checks passed | Command output |
| Session 2 static/security | RuboCop, Zeitwerk, Brakeman, bundler-audit | 159 files/0 offenses; eager load passed; 0 Brakeman warnings; 0 known gem vulnerabilities | Command output |
| Cloud overlay | GKE static overlay validation | 29 resources rendered; no live cloud or Terraform binary | Session 2 report |
