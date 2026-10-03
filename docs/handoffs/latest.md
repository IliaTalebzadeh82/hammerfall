# Current handoff — Phase 20 COMPLETE; Phase 21 NOT STARTED

Updated: 2026-10-04. Phase 20 Identity & Security is closed after the exact-SHA
hosted `CI` gate. See the [final review](../security/phase-20-final.md),
[Phase 20 ExecPlan](../plans/phase-20-execplan.md), [ADR-016](../adr/016-first-party-identity-and-sessions.md)
and [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md) for decisions,
verification and rollout constraints. The closure commit and Actions run are
identified by the commit containing the final review and the successful `CI`
workflow whose `head_sha` equals it; exact IDs appear in the final closure response.

Phase 20 established bcrypt first-party credentials, opaque revocable PostgreSQL
sessions, encrypted HttpOnly host-only cookies, same-origin CSRF, server-derived
command identity, seller ownership/locked self-bid protection, owner/operator
lifecycle authorization, authenticated Cable admission, shared Redis rate limits,
32 KiB pre-parse body bounds, versioned HMAC idempotency digests with retained
legacy/previous-key replay, and bounded security events. PostgreSQL remains the
sole auction authority. The active smoke/browser/multi-instance clients now use
that identity contract. Final local evidence: 494 backend examples/0 failures/4
pending, 76 frontend tests, 8 real browser scenarios passed plus the separate
opt-in worker-outage scenario, authenticated Compose/Kafka/closer smokes, A/B
session/revocation/replay/concurrency, Redis degradation, body 413, static audits
and GCP overlay validation.

Accepted limits: no professional penetration test or live cloud deployment; GKE
Gateway upstream byte buffering and cloud secret rollout unproven; Redis-loss
fallback quotas are per process; a Cable socket established before revocation may
receive public hints until disconnect; retained HMAC keys must remain until rows
are physically pruned. Initial HMAC rollout must drain old executors before new
writes. Phase 22 owns operational durability and release exercises.

Next requested phase: **Phase 21 — Marketplace Trust & Auction Policy**. Begin
only on explicit request. Do not start it from this handoff alone.
