# Security

Phase 20 Sessions 1–2 add first-party login, revocable PostgreSQL-backed sessions,
CSRF headers, authenticated command identity, seller ownership, operator lifecycle
permissions and authenticated Action Cable handshakes. See [ADR-016](adr/016-first-party-identity-and-sessions.md),
the [Session 1 report](security/phase-20-session-1.md) and [Session 2 report](security/phase-20-session-2.md). `bidder_id` is rejected
on HTTP commands. Public user creation is removed. The API remains a local
development system, not a public service.

Rails API mode now adds cookie middleware for opaque session transport;
there is still no permissive CORS policy. Rails-native endpoint rate limits use a
dedicated shared Redis cache. Authentication and Cable fail closed when Redis is
unavailable; bid/lifecycle admission falls back to half-size process-local quotas.
All quota rejections happen before command ownership and return structured 429
with `Retry-After`. A 32 KiB early Rack guard and local nginx limit reject bodies
before Rails JSON parsing. Cloud Gateway edge enforcement remains unverified;
the application guard still applies to Rails. See [the API contract](api.md).
The versioned API allowlists resource attributes, rejects nested/unknown fields,
bounds lists, validates IDs/money, and returns deliberate public JSON with stable
expected-error codes. It does not broadly rescue unexpected programming errors.

Ignore .env, Rails master keys, dependency folders, logs, and generated build files.
.env.example contains only explicitly local dummy credentials. Never reuse these
for deployment. Rails generates a development secret in a volume shared by the
two local API replicas; production must receive
SECRET_KEY_BASE, DATABASE_URL and a comma-separated API_ALLOWED_HOSTS allowlist
from its environment. An empty host allowlist prevents production boot. No encrypted credential
file is needed for the current app.

RuboCop and Brakeman run in checks; bundler-audit runs in CI and is available
locally. Dependency checks reduce risk but are not a security guarantee.

Bounded structured security events cover authentication, authorization, rate
limits and backend degradation, oversized requests, privileged lifecycle
actions and Cable admission. They carry category/outcome/reason and existing
trace correlation only, never actor/IP/login labels or private payloads. Events
go to the application log and bounded metrics, not a durable audit table.
Production log access and retention must be restricted by the deployment's
logging platform; no retention guarantee is claimed for local Docker logs.


Phase 3 established representation/data privacy. Public auction/history and maximum acknowledgements omit maxima, priorities
and automatic origins; parameter/SQL bind/model-inspection filtering is tested.
No private maximum read/list/delete endpoints exist. Session 1 removes supplied
actor authority and denies seller self-bids; operators with database access can
still access plaintext maxima.
An automatic visible offer may reach its ceiling by design, without labelling it as
that ceiling. Do not expose this incomplete local API to untrusted networks.

Phase 5 idempotency scope now uses the authenticated actor ID at HTTP entry.
Raw keys and private payloads are not persisted in the idempotency table. New
key digests use HMAC-SHA256 with an explicit algorithm version and key ID; retained
legacy SHA-256 rows remain replayable until physical pruning. Canonical request
fingerprints remain SHA-256 and snapshots use only public API serializers. The
keyring must be shared across replicas and old key IDs stay configured while any
row using them remains. Production boot requires a readable external keyring;
development/test alone use a fixed local-only key. See
[ADR-017](adr/017-versioned-keyed-idempotency-digests.md). Clients should still
use unpredictable keys. Legacy SHA rows retain their offline-guessing exposure
until pruning.
Fingerprints are not encryption or protection against an operator reading the
plaintext database. Opaque keys should be sufficiently unique; do not encode secrets
in them. Never reinterpret actor scope or expose retained records as a public list.
Conflict/replay responses retain the original public privacy boundary. New key,
fingerprint and response attributes are filtered from ordinary model/bind logging.

Phase 6 renders auction text through React, never dangerouslySetInnerHTML.
Session 1 removes actor selection and adds a login/logout control. No credentials or private inputs enter
URLs or public environment variables. The public API client/types/views have no
maximum/priority/origin display fields. The signed-in actor's own unresolved maximum
is temporarily stored in same-tab sessionStorage for retry; resolved storage is
removed, unsubmitted inputs clear on logout, and no confirmed ceiling is
inferred from acknowledgements. Storage access is not an authentication boundary.
Local host allowances are explicit; production CORS was not broadened. See ADR-007.

## Phase 7 public transport boundary

Cable exposes only public auction ID/revision/type. Maxima, priority, bid origin,
actor identity, idempotency keys and command outcomes never enter notifications.
Malformed/unknown subscriptions are rejected. Exact allowed origins remain enabled;
production has no implicit same-host allowance. No private actor channel exists.
Cable now requires a live session at handshake and subscription, while hints
remain public data. A socket established before revocation/expiry can continue
receiving public hints until disconnect. A real Chrome/Compose check observed
the public-only payload after logout and rejected reconnect. Connection and
subscription rate limits are bounded; production connection capacity remains unknown.

## Phase 11 projection privacy

The Kafka projection consumer accepts only the public v1 data allowlist. The
PostgreSQL rebuild slices the same fields from `AuctionPresenter`; the Redis
value adds only revision, event/source and freshness metadata. Redis and the
eventual endpoint omit private maximums, priority, bid origin and idempotency
material. Focused tests and a live private-maximum update checked the raw key;
this is representation privacy, not authorization or protection against an
operator with Redis/database access. Avoid logging raw values, event payloads
or keys from client commands. The incomplete local API remains unsuitable
for public deployment.
