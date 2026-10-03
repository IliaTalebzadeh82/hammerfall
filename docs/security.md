# Security

Phase 1 exposes business endpoints for local development, with no authentication
or authorization. A supplied bidder_id is a demo actor selector, not proof of
identity. Anyone with API access can create identities/auctions, submit bids as any
existing user, and invoke lifecycle actions. Do not expose it as a public service.

Rails runs API-only middleware; no session or permissive CORS policy is introduced.
Authentication, authorization, CSRF strategy, and rate limiting are scheduled for
[Phase 20 — Identity & Security](phases/phase-20.md); none is implemented yet.
The versioned API allowlists resource attributes, rejects nested/unknown fields,
bounds lists, validates IDs/money, and returns deliberate public JSON with stable
expected-error codes. It does not broadly rescue unexpected programming errors.

Ignore .env, Rails master keys, dependency folders, logs, and generated build files.
.env.example contains only explicitly local dummy credentials. Never reuse these
for deployment. Rails generates a development secret; production must receive
SECRET_KEY_BASE, DATABASE_URL and a comma-separated API_ALLOWED_HOSTS allowlist
from its environment. An empty host allowlist prevents production boot. No encrypted credential
file is needed for the current app.

RuboCop and Brakeman run in checks; bundler-audit runs in CI and is available
locally. Dependency checks reduce risk but are not a security guarantee.


Phase 3 provides representation/data privacy, not complete authorization-based
secrecy. Public auction/history and maximum acknowledgements omit maxima, priorities
and automatic origins; parameter/SQL bind/model-inspection filtering is tested.
No private maximum read/list/delete endpoints exist. Supplied actor IDs still permit
impersonation and probing; operators can access plaintext maxima in PostgreSQL.
An automatic visible offer may reach its ceiling by design, without labelling it as
that ceiling. Do not expose this unauthenticated local API to untrusted networks.

Phase 5 idempotency scope uses the supplied actor ID and is not authentication.
Raw keys and private payloads are not persisted in the idempotency table; keys and
canonical requests use SHA-256 digests, and snapshots use only public API serializers.
An unkeyed key digest permits an offline dictionary attack against low-entropy
client keys if the idempotency table is stolen. Phase 12.5 explicitly deferred
HMAC conversion to Phase 20: retained digests are unversioned, so a
safe rollout needs legacy lookup, key versions, shared multi-instance secrets
and a rotation policy that preserves replays until pruning. Clients should use
unpredictable keys. This decision does not treat SHA-256 as secret protection.
Fingerprints are not encryption or protection against an operator reading the
plaintext database. Opaque keys should be sufficiently unique; do not encode secrets
in them. Never reinterpret actor scope or expose retained records as a public list.
Conflict/replay responses retain the original public privacy boundary. New key,
fingerprint and response attributes are filtered from ordinary model/bind logging.

Phase 6 renders auction text through React, never dangerouslySetInnerHTML. Actor
selection remains visibly unauthenticated. No credentials or private inputs enter
URLs or public environment variables. The public API client/types/views have no
maximum/priority/origin display fields. The selected actor's own unresolved maximum
is temporarily stored in same-tab sessionStorage for retry; resolved storage is
removed, unsubmitted inputs clear on actor changes, and no confirmed ceiling is
inferred from acknowledgements. Storage access is not an authentication boundary.
Local host allowances are explicit; production CORS was not broadened. See ADR-007.

## Phase 7 public transport boundary

Cable exposes only public auction ID/revision/type. Maxima, priority, bid origin,
actor identity, idempotency keys and command outcomes never enter notifications.
Malformed/unknown subscriptions are rejected. Exact allowed origins remain enabled;
production has no implicit same-host allowance. No private actor channel exists.
Demo identity and lifecycle APIs are still unauthenticated; origin checks do not
replace authentication, authorization, rate limits or connection capacity controls.

## Phase 11 projection privacy

The Kafka projection consumer accepts only the public v1 data allowlist. The
PostgreSQL rebuild slices the same fields from `AuctionPresenter`; the Redis
value adds only revision, event/source and freshness metadata. Redis and the
eventual endpoint omit private maximums, priority, bid origin and idempotency
material. Focused tests and a live private-maximum update checked the raw key;
this is representation privacy, not authorization or protection against an
operator with Redis/database access. Avoid logging raw values, event payloads
or keys from client commands. The local unauthenticated API remains unsuitable
for public deployment.
