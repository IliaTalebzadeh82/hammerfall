# Phase 20 Session 2 — security controls

Status: Session 2 checkpoint, 2026-10-03. Phase 20 remains incomplete.

## Evidence and decisions

This report covers focused Session 2 proofs. Decisions are tracked as ADOPT, REJECT, DEFER or NEEDS EVIDENCE in the Phase 20 ExecPlan.

### Initial real-path evidence

The preexisting Compose API bundle lacked bcrypt, and login initially returned 500. After installing the locked gem and preparing the development DB, a Chrome/Playwright page at `http://localhost:3000/` exposed a second defect: A and B had different auto-generated development `secret_key_base` values. Login could succeed on one replica while GET session returned 401 on the other. Sharing the development `api_tmp` secret volume between both API containers fixed it; production remains required to provide one shared `SECRET_KEY_BASE`.

With the corrected stack, Chrome sent login through the Next.js same-origin rewrite (201 on A), got session and CSRF through B (200), placed an authenticated bid (201), received a Cable welcome and confirmed subscription, logged out (204), got 401 on subsequent session GET, and received a Cable disconnect on reconnect. Anonymous bid returned 401. The cookie was hidden from `document.cookie`. A separate direct two-replica proof logged in through A, resolved the same actor through B, accepted a bid through A, replayed the identical bid and ID through B with `Idempotency-Replayed: true`, revoked through B, and got 401 through A. These are local Compose/Chrome proofs using a dedicated development fixture auction and identity; they do not prove a cloud deployment.

### Design before implementation

**Limiter classes.** Authentication: two counters (IP and normalized login identifier digest), conservative short windows to bound bcrypt work. Bid and maximum commands: per authenticated actor/operation and IP secondary limits, before the idempotency executor and auction lock. Privileged lifecycle: per actor/operation, separately from bidding. Cable: connection establishment by IP and subscription churn by session; never count broadcasts. Public reads remain outside this Session 2 limiter. Every rejection is a pre-command 429 with a stable public code and `Retry-After`; frontend must treat it as a definite rejection. No raw login, IP or actor ID enters metric labels.

**Implementation choice.** Rails 8.1's `ActionController::RateLimiting` supports named limits, a supplied store and an atomic `increment` callback. Its default cache can be process-local, so use a dedicated shared Redis store. `RedisCacheStore` catches connection errors by default and can return nil; configure a raising error handler so outage behavior is explicit. Cable needs a small direct check outside controllers. Do not use the limiter for bid serialization. Official sources: [Rails rate limiting API](https://api.rubyonrails.org/v8.0.5.1/classes/ActionController/RateLimiting/ClassMethods.html), [Rails caching guide](https://guides.rubyonrails.org/caching_with_rails.html), and the installed Rails 8.1.3.1 `rate_limiting.rb`/`redis_cache_store.rb` implementations.

**Redis failure policy.** Login fails closed with a distinct 503 before bcrypt if the distributed limiter is unavailable; existing authenticated sessions and PostgreSQL bids remain possible. Bid, maximum and privileged mutations use a conservative per-process temporary fallback counter while Redis is unavailable. This loses global cross-replica quota during outage and permits more traffic by switching replicas, but preserves a bounded local admission path and PostgreSQL correctness. Cable handshake/subscription fail closed while Redis is unavailable, since hints are optional. Emit bounded degradation telemetry. A failed limiter never writes an idempotency record or auction result.

**Body bound.** Use 32 KiB for API request bodies. Nginx local edge rejects above that size, while an early Rack middleware reads at most limit + 1 bytes from `rack.input`, rejects a too-large declared length immediately, and replaces accepted input with a bounded `StringIO` before Rails parameter parsing. This is a Rails parser bound, not a claim that Puma or a gateway buffers zero bytes. Cloud Gateway request-size support must be verified before any manifest change.

**Keyed digest.** Keep logical scope `(actor_id, operation, raw client key)`. Add `digest_version` (1 = legacy SHA-256, 2 = HMAC-SHA256) and separate `digest_key_id` for HMAC secret version. Keep the existing unique `(actor_id, operation, key_digest)` index and 64-byte hex representation. For each command, take a PostgreSQL transaction-scoped advisory lock derived from actor, operation and a transient SHA-256 of the raw key, then look up current/previous HMAC digests and legacy SHA in that order before claiming a new current-key row. The advisory lock serializes differently versioned claims within the new code; rollout must drain old code before mixed-version traffic because old code does not take that lock. New writes use only current HMAC. Key material comes from validated file/env configuration shared by all replicas; production has no built-in key. A key is retireable only after *every* row written with it is physically pruned, since expiry alone does not free a key. Fail validation if a retained key ID lacks configured key material. Preserve fingerprint, response, uniqueness and seven-day default pruning behavior.

## Failure matrix

| Dependency/failure | Security behavior | Availability behavior | Auction authority |
| --- | --- | --- | --- |
| Redis limiter unavailable | Login and new Cable admission fail closed; bid/maximum/lifecycle use half-quota per-process fallback | Existing sessions and admitted bids continue; global quota cannot be enforced across replicas during outage | PostgreSQL unchanged |
| Session DB unavailable | Authentication cannot complete | Protected mutations unavailable | PostgreSQL unavailable |
| Expired session | 401 before command | Re-login required | Committed result unchanged |
| HMAC config invalid or retained key missing | Invalid file fails boot; missing retained key ID raises before claim | Commands unavailable until corrected | No command accepted with unsafe digest configuration |
| Cable session expires or is revoked | Reconnect and new subscriptions rejected; established socket may receive public change hints | Existing socket may remain open until disconnect | No effect on auction state; hint payload excludes private maxima |
| Oversized request | Nginx or early Rack guard responds 413 JSON before Rails parsing | Request denied | No command entered |

## Implementation and focused evidence

| Control | Actual check and result |
| --- | --- |
| Shared limiter | Rails 8.1 `rate_limit` uses a dedicated RedisCacheStore namespace. Login has IP 10/min and normalized-login 5/min limits; bids/maxima actor 20/10s plus IP 60/10s; lifecycle actor 10/min; Cable connection IP 20/min and subscription session 40/min. Alternating direct requests to replicas A/B produced ten 401 wrong-login responses then a shared 429 on the eleventh. The 429 has `rate_limited` and `Retry-After`; a rejected bid leaves no new idempotency record. Actor isolation passed in the request spec. |
| Redis loss | A temporary second Puma process on port 3010 with an invalid Redis URL returned login 503 `limiter_unavailable` before bcrypt, served an existing authenticated session, and accepted a bid using local fallback. Cable admission fails closed by policy. Fallback counters are process-local and cannot guarantee one cluster-wide quota. |
| Body bound | `RequestBodyLimit` precedes Rails parameter parsing. Specs cover declared oversize without a read, unknown-length stream read of only 32,769 bytes, exact 32 KiB acceptance, malformed small JSON and no login/bid/max mutation. Real 33,000-byte requests returned 413 JSON through local Nginx, Next rewrite and direct chunked Rails. This does not prove GKE Gateway's own buffering limit. |
| HMAC idempotency | New rows use HMAC-SHA256 with digest version 2 and a key ID. Real PostgreSQL specs cover current/previous key replay, legacy SHA replay, changed-payload conflict, actor isolation, early retirement rejection and ten-way concurrent claims. The advisory lock precedes lookup/claim; old code must be drained before rollout. Direct A/B replay returned the original bid ID and `Idempotency-Replayed: true`; the stored row was version 2, `local-v1`, 64 hex characters. Production needs the same validated keyring file on every API replica. |
| Security events | Bounded authentication, authorization, limiter, oversized-body, privileged-action and Cable categories flow through approved `Observability` fields. No token, IP, login, actor ID, raw key or private maximum is accepted as an event dimension. Request and direct event specs verify emission and the fixed taxonomy. Logs and metrics need deployment-specific access and retention controls. |
| Cable revocation | Chrome verified welcome/subscription through the Next rewrite; after logout, reconnect was rejected. An already open socket received exactly a public `auction.changed.v1` hint with auction ID and revision after logout. This is the adopted public-hint policy; a fresh subscription requires a live database session. |
| Public users | The endpoint returns only IDs/names of users with public bids, avoiding enumeration of new accounts without public auction participation. Login, role, password digest and session fields are absent. |
| Session replacement | A request spec verified that a second login changes the encrypted cookie, destroys the first PostgreSQL session row, and keeps the new session usable. CSRF and unauthorized-mutation regression remains in the identity request suite. |

The local Compose setup required the locked bcrypt gem in its shared bundle and a prepared development database. A real browser then exposed per-replica generated `secret_key_base` mismatch. Sharing the development `api_tmp` volume repaired the Compose identity path. Production must supply one shared `SECRET_KEY_BASE`; this local repair is not a cloud proof.

## Adversarial review and limits

- Replica switching did not bypass the shared healthy Redis quota. During Redis loss, the documented local fallback can be multiplied by switching replicas; PostgreSQL bid legality and serialization remain unchanged.
- Failed 429/413 admission occurs before idempotency claim and is a definite client rejection; the web client was updated accordingly. Existing 401 reauthentication and ambiguous network/5xx retry behavior remains.
- Retained legacy SHA and prior-HMAC rows replay. A removed key with any physically retained row, including an expired row, fails validation. All instances must receive the same keyring before traffic; mixed old/new executor code is excluded from rollout.
- The bounded Rack guard protects Rails parsing, while upstream Nginx/Puma/Gateway may buffer data earlier. The GKE Gateway edge byte limit has not been proven.
- Existing Cable sockets can continue receiving public hints after revocation until disconnect; no private maximum enters the hint. Session expiry/revocation is enforced on new handshake/subscription.
- No paid GCP resources were created or applied. Terraform was unavailable locally, so the new metadata/IAM change has static overlay validation but no local `terraform fmt`/schema validation. Session 3 owns the full browser/Compose/hosted CI gate, legacy client migration, and final Phase 20 closure.
