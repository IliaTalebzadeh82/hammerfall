# Current handoff — Phase 20 Identity & Security, after Session 2

Updated: 2026-10-03. Phase 20 is active but **not complete**; Phase 21 has
**not** started. Resume in a fresh conversation from the [Phase 20 ExecPlan](../plans/phase-20-execplan.md),
[Session 2 report](../security/phase-20-session-2.md), [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md),
[ADR-016](../adr/016-first-party-identity-and-sessions.md) and [Phase 20 spec](../phases/phase-20.md).

Session 1 established authenticated PostgreSQL sessions, CSRF, actor-derived
commands, owner/operator authorization, seller self-bid protection, Cable
admission and browser same-user retry. Session 2 added shared Redis rate
limits with endpoint-specific outage behavior, a 32 KiB pre-parse body guard,
versioned HMAC idempotency digests with legacy/previous-key replay, bounded
security events, and a public-hint-only policy for already open Cable sockets
after revocation. Public user listing now includes only users with public bids.

Focused live evidence: Chrome through the Next rewrite passed login, cookie,
CSRF bid, Cable, logout and rejected reconnect. A/B Rails replicas shared
identity, revocation, same-key bid replay and Redis quota. A Redis-outage
process rejected login but allowed an existing session and locally limited
bid. Oversized Nginx/Next/chunked Rails requests returned 413 before Rails
JSON parsing. Local Compose needed the generated Rails secret shared across
replicas; production must distribute one real SECRET_KEY_BASE and one
validated HMAC keyring. See the Session 2 report for method and limitations.

Session 2 final backend suite: 493 examples, zero failures, four pending,
seed 4494, isolated Redis DB 15 and pool 15. Frontend: 76 tests and
types/lint/format/build passed. RuboCop: 159 files, zero offenses; Zeitwerk,
Brakeman (zero warnings) and bundler-audit (zero known vulnerabilities) passed.
The ExecPlan Evidence Index retains focused and live proof details.

Next Session 3: adapt legacy smoke and Playwright clients to authenticated
transport, run full Compose/browser/multi-instance/hosted CI gates, final
adversarial review and documentation reconciliation. Do not start Phase 21.
GKE Gateway edge buffering and live cloud secret rollout remain unverified;
Terraform was unavailable locally and no paid GCP apply occurred.
