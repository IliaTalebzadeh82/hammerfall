# Phase 20 — Identity & Security

Status: Complete after Sessions 1–3; final local and hosted evidence in the
[Phase 20 final review](../security/phase-20-final.md). Phase 21 has not started.

## Goal

Replace the demo actor trust model with explicit identity and authorization, and close the most important public-exposure security gaps without changing auction correctness authority. Answer who the actor is, which resource they own, what they may do, which operations are privileged, how abusive traffic is bounded, and how authentication failure affects retries, bidding and realtime connections.

## Prerequisites and decisions

Phase 19 is complete. Read the latest handoff, [security](../security.md), [production readiness](../production-readiness.md), the API and existing idempotency/Cable contracts before implementation. Record the browser and API session/token strategy in an ADR; do not select JWT by convention. Specify identity migration and retained command replay behavior before changing actor scope. PostgreSQL remains auction authority; Redis and rate limiting cannot determine bid legality or outcome.

## Scope and requirements

- Authenticate real actors rather than trusting supplied `bidder_id`. Define API identity propagation, browser login/session behavior, Action Cable connection and subscription authentication, expiry and revocation behavior, and CSRF strategy appropriate to the chosen credentials.
- Define bidder/buyer, seller, operator/admin and system/background capabilities. Enforce auction ownership, bidder identity, seller restrictions, lifecycle permissions, operator-only actions, reconciliation/admin operations and access to private maximums. Identity must permit enforcing that sellers cannot bid on their own auctions; additional marketplace policy belongs to Phase 21.
- Bound bid and maximum-bid commands, authentication endpoints, lifecycle/operator endpoints and appropriate WebSocket connections/subscriptions. State actor/IP limits and explicit behavior when the limiter or backend is unavailable. Do not let a limiter become auction authority.
- Add a pre-parse public request-body size limit at the edge and, where useful, the application. Verify chunked and streamed requests as well as parsed JSON limits.
- Replace raw SHA-256 idempotency key digests with a keyed/HMAC strategy. Design key versions, legacy digest lookup, rotation, shared multi-instance secret distribution and retention so historical same-key replay remains correct. Preserve command identity, payload conflict behavior and private-data filtering.
- Record security-relevant authentication, authorization, throttling and privileged-operation events without credentials, private maxima, raw idempotency keys, tokens or secret values. Define useful retention/access boundaries.

## Verification

Test impersonation, unauthorized lifecycle mutation, seller self-bidding, horizontal privilege escalation, private-maximum probing, replay under a changed identity, expired sessions during retry, malformed and oversized input, unavailable limiter behavior, and unauthorized Cable connection/subscription. Use real PostgreSQL and relevant multi-instance/integration checks where behavior depends on concurrency or retry. Run focused tests and the relevant broad regression, lint and local startup checks; record actual evidence and limits.

## Definition of done

Identity and authorization are explicit across HTTP, background and Cable boundaries; public-exposure basics above are verified without changing PostgreSQL auction authority or historical replay semantics. Update ADRs, API/security/operational docs, progress and handoff with evidence. No known serious correctness or security bug remains in phase scope.

## Out of scope

This is not a generic penetration-testing project or a full marketplace policy implementation. Do not start Phase 21 without an explicit request.
