# Current handoff — Phase 20 Identity & Security, after Session 1

Updated: 2026-10-03. Phase 20 was explicitly authorized. Session 1 completed
the identity foundation and is checkpointed; Phase 20 is **not complete** and
Phase 21 has **not** started. Resume in a fresh conversation from the
[Phase 20 ExecPlan](../plans/phase-20-execplan.md),
[Session 1 report](../security/phase-20-session-1.md),
[ADR-016](../adr/016-first-party-identity-and-sessions.md) and
[Phase 20 spec](../phases/phase-20.md).

Rails now authenticates first-party users through revocable PostgreSQL-backed
opaque sessions in encrypted HttpOnly cookies, checks CSRF on unsafe requests,
derives bid/maximum actor identity from the session, and rejects client
`bidder_id`. New auctions have a seller; owner/operator policy guards lifecycle
routes and the locked auction domain rejects seller self-bids. Cable requires
a live session at handshake/subscription. The web has login/logout and preserves
ambiguous intentions across expiry for same-user replay. Historical idempotency
actor/fingerprint semantics were preserved and tested through the new HTTP path.

Evidence: focused identity/Cable/model/seed tests 34/0; selected requests 79/0;
isolated-Redis backend suite 470/0 with three gated live-Kafka pending; frontend
75/0 plus lint/types/format/build; Ruby lint, Zeitwerk, Brakeman and advisory
audit passed. Initial backend run against development Redis DB 0 had stale
projection-key collisions; DB 15 resolved them. Exact methods and logs are
in the ExecPlan Evidence Index.

Next: verify real Next rewrite cookie/CSRF/Cable behavior and multi-replica
login/logout, then implement Phase 20 rate limits, body bounds, versioned HMAC
idempotency digests/rotation, full security events and Cable expiry policy.
Legacy smoke/Playwright clients still use removed actor selection and need
adaptation before final Compose/browser/hosted CI. Open sockets can retain
public hints after logout until disconnect. No GCP apply or paid resource was
created. Phase 19 remains complete as a static GCP reference only.
