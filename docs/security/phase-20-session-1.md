# Phase 20 Session 1 — identity/security foundation

Status: Session 1 foundation completed, 2026-10-03. This is not a Phase 20 completion claim.

## Prior trust model and attack surface

Before Session 1, browser → same-origin Next.js rewrite → Rails API accepted `bidder_id` as identity. Any client can create/list users, create/edit/transition auctions and submit bids or maxima for another user. The API/Action Cable origin configuration protects some browser connections but does not authenticate users. PostgreSQL is the source of auction and idempotency truth; Redis projection/Sidekiq/Kafka/Cable are derived or delivery paths. Background closer, sweep, consumers and reconciliation run from internal processes; the public close/lifecycle routes are a separate privilege boundary. The Rails/Puma request parser has no pre-parse byte bound; local nginx and GKE Gateway bounds require Session 2 verification. The public maximum serializer omits ceilings but actor impersonation permits probing.

Threats in scope: impersonation, horizontal replay, seller self-bidding, unauthorized lifecycle/maximum access, session theft/replay/staleness, CSRF, login guessing, body/command/socket floods, idempotency-key digest disclosure, and secret logging. PostgreSQL compromise or arbitrary code execution is outside this session's mitigation claim.

## Endpoint authorization matrix

| Operation | Anonymous | Authenticated buyer | Seller/owner | Operator | Internal system |
|---|---|---|---|---|---|
| List/detail/public state/history/users | Yes, public fields only | Yes | Yes | Yes | Yes |
| Login | Yes, credentials | Yes | Yes | Yes | No |
| Logout/current session | No | Own | Own | Own | No |
| Place bid / set maximum | No | Yes, except own sale | No on own sale | No on own sale | No |
| Create draft | No | Yes; becomes seller | Yes | Yes | Fixture/maintenance only |
| Edit draft / cancel | No | No on others | Own | Yes | No normal job |
| Schedule / activate | No | No | No | Yes | Activation scheduler if explicitly internal |
| Close HTTP action | No | No | No | Yes | Closer calls model directly |
| Reconciliation trigger/admin inspection | No | No | No | Operator only if exposed | Internal task |
| Private maximum read/list | No endpoint | No endpoint | No endpoint | No endpoint | Database maintenance only |
| Cable auction hint | Connection requires session | Public hint only | Public hint only | Public hint only | Publisher internal |

The operator role is deliberately narrow: lifecycle intervention. An auction with unknown legacy seller is operator-managed. Authorization precedes the domain transaction; seller self-bid also has a post-lock domain guard. PostgreSQL still decides timing, amount, close and winner.

## Options, decision and migration

Compared Rails CookieStore, a PostgreSQL-backed opaque cookie session, a bearer token and JWT against revocation, multi-instance, CSRF, Cable and local use. [ADR-016](../adr/016-first-party-identity-and-sessions.md) adopts the opaque session and records alternatives and official Rails/OWASP sources. Existing User rows have no proof of identity: migration cannot silently assign a known password. New login/password provisioning is explicit; local seeds are only local. Existing auctions' seller remains unknown until assigned; new drafts require an authenticated seller. Historical idempotency records retain their actor ID and key digest; authenticated same-user replay reaches the same scope, while a different actor cannot. Session expiry returns 401 before key claim and the same user may log in again with the unchanged intention.

## Implemented boundary, evidence and unresolved risks

The migration adds nullable login/password digest to preserve uncredentialed legacy
users, a narrow member/operator role, nullable seller ownership for old auctions,
constraints against seller as leader/winner, and a session table with unique token
digest. New HTTP drafts receive the authenticated seller. Local development seeds
provision four explicitly local identities; existing accounts receive no new
password or role, even if they use a demo login. Auction seller ownership is
immutable after creation. Public `POST /users` is removed. Login issues a random 256-bit secret in
an encrypted HttpOnly SameSite cookie; only its digest is stored. Session expiry
uses PostgreSQL clock time, logout deletes the row, and a bounded prune task
cleans expired rows. GET session exposes a derived CSRF token, not the session
secret. Unsafe authenticated requests require its header; login requires a JSON
custom header and permissive credentialed CORS is absent.

HTTP bid/max controllers reject `bidder_id` and pass `current_actor.id` into the
unchanged idempotent command. A focused test first writes a legacy-scope record
through the old application entry point, then replays it through authenticated
HTTP with the same actor/key/payload. Session expiry returns 401 before key claim;
same-user reauthentication replays the original outcome. Other users get a
different scope. Seller self-bids fail after the PostgreSQL auction lock, including
private maxima. Owner/operator policy covers draft and lifecycle routes. Cable
requires the same live session at handshake and subscription; hints stay public.

The web now logs in/out and derives its actor from GET session. A pending intention
retains its original actor ID only as a client-side same-user retry guard. A 401
preserves the intention and requires reauthentication; a retry uses the original
key and payload with a fresh CSRF token. Credentials are not stored in browser
storage. The API's public maximum acknowledgement still excludes ceilings.

The focused identity/Cable/model/seed run passed 34 examples (seed 5919), including
wrong login, missing login header, logout/expiry, CSRF, impersonation, horizontal
replay, retained legacy outcome replay, seller manual/maximum denial, owner/operator
denial, Cable connection/subscription and ordinary log filtering. The selected
request regression passed 79 examples. The isolated-Redis backend suite passed
470 examples, zero failures, three existing gated live-Kafka pending (seed 13658).
The first broad run used the development Redis DB 0 and had 16 projection failures
from stale keys colliding with reused test auction IDs; rerunning on test DB 15
resolved them. Frontend lint/format/types/build and 75 Vitest tests passed.
RuboCop passed 146 files; Zeitwerk eager load passed; Brakeman found zero warnings;
the updated Ruby advisory database found zero known vulnerabilities. See the
[Evidence Index](../plans/phase-20-execplan.md) for commands and logs.

Session 2 owns login/command/Cable limits, body bounds, HMAC migration, key
rotation, full security events, open-socket expiry policy and multi-instance
live proof. Session 3 must update legacy smoke/Playwright clients, verify the
Next rewrite's cookie/header behavior, Compose startup, hosted CI and broad
final gates. An established Cable stream may continue receiving public hints
after logout until it disconnects. The seven-day idempotency digest remains
unkeyed. No penetration test, live cloud deployment or production security
claim is made.
