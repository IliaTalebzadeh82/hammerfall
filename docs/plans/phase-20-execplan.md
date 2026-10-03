# Phase 20 ExecPlan — Identity & Security

Status: Active Phase 20; Session 1 identity foundation completed and checkpointed. Phase 21 has not started.
Current milestone: Resume in fresh Session 2 for remaining security controls.
Completed: Trust/endpoint inventory; [ADR-016](../adr/016-first-party-identity-and-sessions.md); bcrypt User credentials and PostgreSQL-backed revocable sessions; login/logout/current-user/CSRF; authenticated HTTP actor propagation; owner/operator policy and immutable seller; seller self-bid guard under lock; authenticated Cable handshake/subscription; minimal browser login/logout/expired retry; create-only local demo identities; focused tests and docs.
Verified: Real PostgreSQL request and channel tests, isolated-Redis backend regression, frontend suite/build, Ruby/TS lint, Brakeman, advisory audit and Zeitwerk (Evidence Index below).
Remaining: Session 2 rate limits and Redis failure policy, pre-parse request-body bounds, HMAC idempotency key migration/versioning/rotation, complete security events, Cable post-handshake expiry policy and multi-instance proof. Session 3 must adapt existing smoke/Playwright clients, run Compose/browser/hosted CI gates and final adversarial review.
Known failures/limitations: Legacy `scripts/smoke-*` and Playwright clients still use removed user creation/actor selection and cannot verify the new API. No live Next rewrite cookie/Cable handshake or multi-replica login/logout check yet. Existing open Cable streams may survive session revocation/expiry until disconnect, but carry public hints only. No rate limits or pre-parse byte bounds; unkeyed idempotency digests remain. No paid cloud work.
Relevant files: `apps/api/app/controllers/api/v1/`, `apps/api/app/models/`, `apps/api/app/channels/`, `apps/web/src/components/auction/session.tsx`, `apps/web/src/lib/api/`.
Relevant ADRs: [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-006](../adr/006-client-command-idempotency.md), [ADR-007](../adr/007-browser-command-intentions.md).
Next-session starting point: Read this plan, latest handoff, Phase 20 spec and ADR-016. First inspect the Session 1 diff and run a targeted real HTTP cookie/CSRF/Cable handshake across the Next rewrite or Compose; then implement Session 2 controls. Use an isolated Redis test DB (`REDIS_URL=redis://127.0.0.1:6379/15`) for projection specs. Do not start Phase 21.

## Decisions

- ADOPT: PostgreSQL-backed opaque sessions, bcrypt credentials, cookie transport, same-origin CSRF header; see ADR-016.
- ADOPT: Preserve existing `actor_id` and fingerprint semantics with server-derived identity; authenticate before idempotency lookup.
- ADOPT: Public auction reads, owner draft management/cancel, operator schedule/activate/close; internal closer remains independent.
- REJECT: JWT and browser-readable bearer storage for the current same-origin client.
- DEFER: Limiter, pre-parse body limit, HMAC key migration/rotation and complete security events to Session 2.
- NEEDS EVIDENCE: post-handshake Cable expiry/disconnect, proxy cookie forwarding, multi-replica login/logout, retained legacy-key replay after deployment. A focused RSpec case proves legacy record replay through new HTTP authentication in one process.

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
