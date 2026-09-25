# Security

Phase 1 exposes business endpoints for local development, with no authentication
or authorization. A supplied bidder_id is a demo actor selector, not proof of
identity. Anyone with API access can create identities/auctions, submit bids as any
existing user, and invoke lifecycle actions. Do not expose it as a public service.

Rails runs API-only middleware; no session or permissive CORS policy is introduced.
Authentication, authorization, CSRF strategy, and rate limiting remain future work.
The versioned API allowlists resource attributes, rejects nested/unknown fields,
bounds lists, validates IDs/money, and returns deliberate public JSON with stable
expected-error codes. It does not broadly rescue unexpected programming errors.

Ignore .env, Rails master keys, dependency folders, logs, and generated build files.
.env.example contains only explicitly local dummy credentials. Never reuse these
for deployment. Rails generates a development secret; production must receive
SECRET_KEY_BASE and DATABASE_URL from its environment. No encrypted credential
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
