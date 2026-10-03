# Phase 20 ExecPlan — Identity & Security

Status: Session 3 local final gate passed; closure requires successful exact-SHA hosted CI. Sessions 1 and 2 are checkpointed; Phase 21 has not started.
Current milestone: Local verification complete; exact-SHA hosted CI is the closure gate.
Completed: Session 1 identity foundation (below); Session 2 real Next rewrite cookie/CSRF/Cable and two-replica identity/replay proof; Redis-backed endpoint-class rate limits with explicit outage policy; 32 KiB early body bound; versioned HMAC idempotency digests with legacy/rotation lookup; bounded security events; post-handshake Cable public-hint policy; narrowed public user listing; Compose development secret sharing. See [Session 2 report](../security/phase-20-session-2.md).
Verified: Session 1/2 evidence below. Session 3 rebuilt Compose, migrated smoke/browser/Phase 17 A/B clients, passed full backend/frontend/browser and supplemental worker-outage gates, direct replica/session/replay/concurrency, Redis outage/limiter/body checks, static audits and 29-resource cloud overlay validation. See [final report](../security/phase-20-final.md) and new Evidence Index rows.
Remaining: Verify hosted CI on the final repair SHA. Do not declare completion until CI passes.
Known failures/limitations: Established Cable sockets may continue receiving public hints after revocation until disconnect. Local fallback limiter quota during Redis outage is per process. GKE Gateway body buffering and live cloud secret distribution are unverified; Terraform binary was unavailable locally. Historical Phase 16/17 chaos/load tooling outside the current smoke/CI gate still uses the retired actor API. No paid cloud work.
Relevant files: `apps/api/app/controllers/api/v1/`, `app/services/rate_limit_store.rb`, `app/services/idempotency/`, `lib/request_body_limit.rb`, `app/channels/`, `apps/web/src/lib/api/client.ts`, `docker-compose.yml`, cloud overlay and Terraform secret metadata.
Relevant ADRs: [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md), [ADR-006](../adr/006-client-command-idempotency.md), [ADR-007](../adr/007-browser-command-intentions.md).
Closure condition: the GitHub Actions `CI` workflow must pass with `head_sha` equal to the commit containing the final report. The exact immutable SHA and run ID are recorded in the final response because a commit cannot contain its own hash or a future run ID. Do not start Phase 21.

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
- DONE: Legacy smoke, Playwright and Phase 17 CI A/B clients migrated; full local Compose/browser gate passed in Session 3. Hosted CI remains.
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
| Session 2 Compose/browser/hosted CI | Deferred to Session 3 | Unrun at Session 2 checkpoint | Legacy clients required adaptation then |
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
| Session 3 Compose rebuild | `docker compose down`, regenerate only `api_tmp`, `docker compose up --build --force-recreate --wait` | Expected services healthy/running; bcrypt present; migrations current; four demo identities; A/B secret fingerprints equal | `/tmp/phase20-compose-rebuild.log` and final report |
| Session 3 application smoke | Authenticated sequential/concurrent/proxy/Kafka/idempotency/closing scripts | All passed, including ten-way same-key races and stale closer locks | `/tmp/phase20-smoke-*.log`; final report |
| Session 3 A/B | `script/phase17_session1.rb`, `script/phase20_final_replicas.rb` | Cross-replica sequential, concurrent, proxy, same-key replay, session, logout and revocation passed | `/tmp/phase20-cross-replica.log`, `/tmp/phase20-final-replicas.log` |
| Session 3 browser | Real Chrome/Playwright full suite plus opt-in worker outage | Full suite 8 passed, 1 opt-in skipped; worker-outage case separately passed | `/tmp/phase20-final-browser2.log`, `/tmp/phase20-browser-worker-outage.log` |
| Session 3 backend/full and focused | isolated Redis DB 15, pool 15 | 494 examples/0 failures/4 pending, seed 28252; focused 29/0 seed 11889 | `/tmp/phase20-final-rspec.log`, `/tmp/phase20-final-focused-security.log` |
| Session 3 frontend/static | Vitest, type/lint/format/build; RuboCop/Zeitwerk/Brakeman/audit | 76 frontend tests; all checks passed; Ruby 162 files/0 offenses, 0 Brakeman warnings, 0 known advisories | `/tmp/phase20-final-web-*.log`, `/tmp/phase20-final-{rubocop,zeitwerk,brakeman,audit}.log` |
| Session 3 degraded/edge | Live shared A/B quota, Redis stop/start, Next 33,052-byte body | 401×5 then 429 A/B; login 503, existing bid 201, new Cable unavailable, Redis recovered; edge 413 | `/tmp/phase20-final-{limiter,redis-outage,cable-outage}.log`; final report |
| Session 3 cloud static | `kubectl kustomize`, `render.py`, `validate.rb` | 29 resources validated; Terraform unavailable; no cloud apply | `/tmp/phase20-k8s-*.yaml`, `/tmp/phase20-gcp-rendered.yaml` |
| Closure CI | Exact final repair SHA GitHub Actions | Required before declaring complete | Final report/response after hosted verification |
| First hosted closure attempt | `CI` run 37158321874, SHA `6c38b59ce9e21404d9990b0dbfb58075f5dfebd7` | Web and full Compose/browser jobs passed. API RSpec failed with default five-connection pool; reproduced locally as four `ActiveRecord::ConnectionTimeoutError` failures in ten-worker cases. Set `RAILS_MAX_THREADS=15` in API job; focused 16 examples then passed. | [Actions run](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37158321874); local focused runs |
