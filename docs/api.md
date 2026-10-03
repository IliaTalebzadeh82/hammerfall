# API — Phase 20 identity and security controls

Base path: `/api/v1`. This API remains for local development. Mutations require
an authenticated session; public reads remain available without login.
Use JSON request bodies with Content-Type: application/json. See
[domain semantics](domain-model.md) for lifecycle and money rules.

## Endpoints

| Method | Path | Behavior |
| --- | --- | --- |
| GET | /users | List ID/name of users with public bids only |
| GET | /session | Current identity and CSRF token; 401 without a live session |
| POST | /session | Login with JSON credentials and `X-Hammerfall-Login: 1` |
| DELETE | /session | Revoke current session; `X-CSRF-Token` required |
| GET | /auctions | List auctions |
| POST | /auctions | Create a draft |
| GET | /auctions/:id | Read one auction |
| GET | /auctions/:id/public-state | Explicit eventual public snapshot with PostgreSQL fallback |
| PATCH | /auctions/:id | Edit allowed fields while draft |
| POST | /auctions/:id/schedule | Schedule a draft |
| POST | /auctions/:id/activate | Activate a scheduled auction within its window |
| POST | /auctions/:id/close | Finalize if due; active but not due returns unchanged |
| POST | /auctions/:id/cancel | Cancel an eligible auction with no bids |
| GET | /auctions/:auction_id/bids | List accepted bid history |
| POST | /auctions/:auction_id/bids | Place an idempotent serialized manual bid; key required |

Create returns 201; reads, edits, and lifecycle actions return 200. Single resources
use `{"data": {...}}`. Lists use `{"data": [...], "meta": {"next_after_id": null}}`.
User/auction lists are ordered by ascending ID, default limit 20, maximum 100. Pass positive
`limit` and optional `after_id`; follow next_after_id until null. These cursors do
not imply authoritative transaction ordering.

## Authentication and authorization

POST `/session` with `{"session":{"login":"demo-alice","password":"..."}}`
and `X-Hammerfall-Login: 1`. The successful 201 returns
`{"data":{"id":1,"name":"...","role":"member"},"csrf_token":"..."}`
and an encrypted HttpOnly SameSite cookie. GET `/session` returns the same
shape for a live session. Send `X-CSRF-Token` on every authenticated POST,
PUT, PATCH or DELETE. DELETE `/session` returns 204. Cookies are host-only,
Secure in production, and expire after 12 hours without silent renewal;
logout revokes the database row immediately for new HTTP/Cable handshakes.
The browser must sign in again after expiry and retry an ambiguous command
with its original key and payload as the **same** user. A different user cannot
retrieve that actor's saved outcome. 401 `authentication_required`, 403
`invalid_csrf` and 403 `forbidden` are pre-command errors, not retained
idempotency outcomes.

Public list/detail/state/history and bidder display names return public fields. `/users`
omits accounts without public bids and never includes login, role or credentials. Any authenticated
user may create a draft and becomes its seller. The seller or operator may edit
a draft or cancel an eligible auction. Only an operator may schedule, activate
or call the HTTP close endpoint; the autonomous closer calls the domain model
internally. Sellers cannot bid or set a maximum on their own auctions.
Existing auctions with unknown pre-migration ownership are operator-managed.
No private maximum read endpoint exists. User creation is removed from HTTP;
credentials are provisioned out of band. Local seed credentials are documented
in [running locally](running-locally.md).

Bid history instead uses ascending auction-local `sequence`, `after_sequence`, and
`meta.next_after_sequence` with the same limits. This replaces Phase 1 after_id for
bids; that old parameter is rejected with 400 to avoid silently restarting a page.
Sequence represents serialized accepted-bid order, not request arrival order.

## Auction input and representation

```json
{
  "auction": {
    "title": "Film camera",
    "description": "Working condition",
    "starting_price": 10000,
    "minimum_increment": 500,
    "starts_at": "2026-09-24T12:00:00Z",
    "ends_at": "2026-09-24T13:00:00Z"
  }
}
```

Use current/future dates when exercising this example. The executable smoke script
constructs dates automatically. All money is integer EUR cents (1..1000000000000).
Description is optional on create and defaults to empty. All other shown fields
except description are required. PATCH uses the same allowlist with partial fields.
Unknown fields, nested objects, and arrays within resource attributes are rejected.
Do not submit status, current_price, winner_id, ID, or timestamps of record creation.
The server initializes current_price to starting_price and chooses draft status.

Responses contain id, title, description, status, currency, starting_price,
current_price, minimum_increment, starts_at, original_ends_at, ends_at, closed_at, current_leader_id, winner_id,
created_at, updated_at. Datetimes are UTC ISO 8601. No model internals are dumped.
Lifecycle actions take no body and never accept client time as authoritative.

## Bid input and representation

Both POST bids and PUT maximum-bid require `Idempotency-Key`; see the contract below.

```json
{"bid":{"amount":10500}}
```

The bidder is the authenticated user; `bidder_id` is rejected if supplied. Money must be an integer JSON number: `10500.5`,
`10500.0`, and `"10500"` are invalid. A bid must meet starting_price if first;
otherwise current_price + minimum_increment. Responses contain id, auction_id,
bidder_id, amount, sequence, currency, created_at. There is no bid edit/delete API or rejected-bid table. The protected endpoints
require an idempotency key. A manual response is the caller’s accepted Bid;
proxy counterbids may already have changed the leader by the same commit. Fetch
auction/history to observe the settled state. Origin is never a public field.

Bids validate fresh status, time and minimum after acquiring the auction row lock.
A stale waiter receives ordinary 422 bid_too_low with the price/minimum observed
inside that transaction; later commits may change them again. Sequence is assigned
by the server and cannot be supplied. Rejections and rollbacks allocate no persisted
sequence. IDs/timestamps remain metadata.

## Expected errors

```json
{
  "error": {
    "code": "bid_too_low",
    "message": "Bid must be at least 10500 cents.",
    "details": {"minimum_bid":10500,"current_price":10000}
  }
}
```

| HTTP | Code | Meaning |
| --- | --- | --- |
| 400 | invalid_request | Missing/wrong root shape, unknown/nested fields, malformed JSON, malformed ID/cursor/limit |
| 404 | auction_not_found | Auction ID does not exist |
| 401 | authentication_required | Missing, revoked or expired session |
| 403 | forbidden / invalid_csrf | Capability denied / missing or incorrect CSRF token |
| 413 | request_too_large | API body exceeds 32 KiB before JSON parsing; no command entered |
| 429 | rate_limited | Quota exhausted before the action; `Retry-After` gives a conservative wait in seconds |
| 503 | limiter_unavailable | Login limiter unavailable; `Retry-After: 5`; no password check or session issuance |
| 422 | validation_failed | Model fields are invalid; details maps field names to message arrays |
| 422 | invalid_state_transition | Edge or transition precondition is invalid |
| 422 | invalid_auction_state | Bid on non-active auction or edit outside draft |
| 422 | auction_not_open | Active status before starts_at |
| 422 | auction_ended | Active status but DB decision time at/after ends_at; details includes public ends_at |
| 422 | bid_too_low | Amount below required minimum |
| 422 | seller_self_bid | Seller attempted to bid on own auction |

These are expected-error mappings, not a catch-all that hides programming failures.
No expected response includes exception class, SQL text, or a stack trace. Arbitrary
unknown routes still follow Rails routing behavior. Matching retained keys replay; a fresh key is a new logical command.

Authentication uses shared Redis quotas of 10 login attempts per IP and five per
normalized login identifier per minute. Bid and maximum routes each allow 20
requests per actor and 60 per IP per 10 seconds; lifecycle routes allow 10 per
actor per minute. Replays count as requests. Cable allows 20 connections per IP
and 40 subscriptions per session per minute. Login and Cable fail closed if
Redis is unavailable; bid/maximum/lifecycle routes use half-size local fallback
quotas per API process. This fallback loses a global quota across replicas but
does not change PostgreSQL bid legality. A 429 or 413 is a definite pre-command
rejection: the client may wait and submit the same unchanged intention/key; it
must treat network/5xx failures as potentially ambiguous. The 32 KiB Rails guard
also covers chunked bodies; local nginx applies the same bound.

## Live demonstration status

The pre-Phase-20 `scripts/smoke-*` clients create users and send `bidder_id`.
They need conversion to authenticated sessions and CSRF headers before serving
as current API smoke checks. Session 1 request specs exercise the new contract
against PostgreSQL; the original scripts remain historical until adapted.


For simultaneous HTTP verification, run `./scripts/smoke-concurrent-bids`. It starts
12 concurrent increasing attempts and eight equal-amount attempts on two fresh
auctions, verifies accepted history/sequences/price/leader and prints outcomes.
Rows remain labelled for inspection. Optional API_BASE_URLS is a comma-separated
list of running Rails URLs for routing requests across independent processes.
This is correctness smoke coverage, not a capacity benchmark.


## Private maximum configuration

PUT `/api/v1/auctions/:id/maximum-bid`:

```json
{"maximum_bid":{"maximum_amount":50000}}
```

Returns 200 for create, increase or same-value no-op:

```json
{"data":{"auction_id":1,"bidder_id":42,"accepted":true}}
```

The acknowledgement intentionally omits even the supplied ceiling and private
priority. No GET/list/delete maximum endpoints exist (404). Unknown fields such as
priority_sequence/origin/bidder_id are 400. The authenticated user is the actor.

Money uses the same strict bounded integer cents validator. New or increased protection covers
starting_price, or exceeds public current_price for a nonleader, or covers the
current leader's own visible price. Partial final increments are allowed for
proxies. A nonleader increase at/below public price is rejected as
maximum_bid_too_low without changing private state or priority. Same amount
preserves priority; a valid increase resets it.

Additional 422 errors: maximum_bid_cannot_decrease and maximum_bid_too_low. They
contain no stored private amount. The latter may contain public current_price.
Existing validation_failed/invalid_auction_state/auction_not_open
contracts still apply, including lifecycle checks for repeated same values.

One command may emit zero, one or two public Bid rows, each with its own sequence.
Equal ceilings can emit equal amounts with different sequences; the earlier private
commitment wins. Public auction current_leader_id is explicit state, and winner_id
remains null until close. Bids do not expose whether they are automatic. A qualifying external commitment in the final 60 seconds adds exactly 90 seconds
to ends_at once, even when no visible row is generated. Same-value no-ops never extend. See ADR-004 for examples and docs/domain-model.md for full rules.

Run `./scripts/smoke-proxy-bidding` for manual-vs-proxy, higher/equal proxy and
simultaneous maximum scenarios. API_BASE_URLS can route the final race across two
running Rails processes. Script output is public state; labelled records remain.

## Deadline and finalization contract

The server captures DB clock_timestamp() after obtaining the auction lock. Client,
Rails, request arrival and transaction-start times do not authorize bidding. Exactly
at ends_at is too late. An expired active auction returns 422 auction_ended with
`details.ends_at` as UTC ISO 8601; already closed/cancelled bidding retains
invalid_auction_state. No private values appear in these errors.

POST close returns 200 with unchanged active state if not due, or closed state if
due/already closed. Draft/scheduled/cancelled close returns 422 invalid_state_transition.
This endpoint cannot force early closure. The same operation powers the independent
closer. Rejected late bids do not themselves change lifecycle state. A delayed closer
can leave active status visible temporarily without permitting any late bid/max.

original_ends_at follows draft edits and freezes on scheduling. ends_at includes
all +90 extensions. closed_at is null until finalization and then records its DB
decision time; it can be later than ends_at. current_leader_id remains visible after
closure, alongside winner_id (both equal, or both null with no bids). These are
public intentional fields, not exposure of private maxima. PATCH remains draft-only;
original_ends_at and closed_at are never writable request fields.

Both manual and maximum endpoints extend once per accepted external commitment
inside `0 < remaining <= 60`. Internal proxy counters do not multiply the extension.
Matching retries with a retained key replay without another evaluation or extension.

## Required idempotency contract

Protected endpoints only:

- POST `/api/v1/auctions/:auction_id/bids`
- PUT `/api/v1/auctions/:id/maximum-bid`

```http
POST /api/v1/auctions/42/bids
Content-Type: application/json
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
X-CSRF-Token: <token from GET /session>

{"bid":{"amount":25000}}
```

Use a fresh key for each new intention and **reuse the same key and semantic payload
when retrying an uncertain outcome**. Keys are opaque, case-sensitive, 1–255 visible
ASCII characters, without spaces or control characters. UUID is allowed, not required.
The scope is authenticated actor + operation + key; retained pre-Phase-20
records with that same actor ID remain replayable by that user. An actor may use the same key independently for bid and max commands.
Reusing it for another auction or amount within one operation is a conflict.
New claims store only a versioned HMAC digest of the raw key. Retained legacy
SHA-256 rows remain replayable until physical pruning. Key rotation does not
change the client's key or command identity; see [ADR-017](adr/017-versioned-keyed-idempotency-digests.md).

The server fingerprints canonical v1 operation/auction/actor/amount data, not raw
HTTP bytes. JSON key order, whitespace and unrelated headers do not change identity.
IDs normalize to integers; money scalar types are retained (10000 is different from
invalid "10000" or 10000.0). Missing amount and null have the same invalid meaning.

| Request | HTTP behavior |
| --- | --- |
| First valid execution | Original 201 bid / 200 maximum response; no replay marker |
| Matching retained retry | Original status and exact saved public JSON; `Idempotency-Replayed: true` |
| Same scope/key, different fingerprint | 409 `idempotency_key_conflict`; no mutation or previous payload disclosure |
| Missing key | 400 `idempotency_key_required` |
| Blank, malformed, too-long key | 400 `invalid_idempotency_key` |

Key errors and conflicts use the existing `{error:{code,message,details:{}}}` envelope.
A replay returns the **historical command result**, including original bid ID,
sequence, created_at or rejection minimum. It is not current state; GET Auction
for that. Completed retries work even after price/leader changes or closure and
never acquire the auction lock, run the deadline clock or settle proxies again.
No additional Bid, maximum priority or +90 extension can result from a replay.

Persisted outcomes are 200/201 successes, 422 DomainError/RecordInvalid responses,
and 404 encountered inside execution (such as missing Auction). Missing actor,
malformed JSON/shape/IDs and invalid keys happen before ownership and are not stored.
Conflicts do not replace the old snapshot. Infrastructure/internal failures roll
back and leave the key retryable; arbitrary 500 responses are not cached. The current
endpoints have no logical Location header to preserve; transport/request-ID headers
are not replayed from storage. Maximum response remains amount-free, including replay.

Retention defaults to seven days from the claim transaction's DB timestamp,
configurable via IDEMPOTENCY_RETENTION_DAYS. Expiry marks prune eligibility only:
existing rows keep reserving keys, even when expired. Once physically pruned, the
same key may execute as a new command. Clients must not assume indefinite protection.
An identical maximum with a **different** key is a new command and may be a domain
no-op; its response is not marked replayed.

Pre-Phase-20 smoke scripts generated a new key per distinct bidding command;
`scripts/smoke-idempotency` reused keys intentionally across two independent API
URLs. These scripts are pending authenticated-client updates.

## Phase 6 presentation metadata

Normal `/api/v1` responses and expected API error renders include `X-Server-Time`,
an ISO 8601 UTC timestamp from the Rails application clock near rendering. The
browser uses it only to estimate countdown clock offset. It does not describe the
post-lock PostgreSQL decision time, guarantee clock synchronization, or authorize
a bid. Network delay and app/database clock skew can affect the estimate.

This header is fresh transport metadata on replay, not part of the saved Phase 5
logical response. Status/body replay contracts and all domain semantics are unchanged.
The frontend uses a transparent same-origin Next rewrite; no CORS-wide production
policy or new maximum read endpoint was added.

## Phase 7 public revision and subscription

Auction responses include `public_revision`, a nonnegative bigint (JSON number).
Creation/legacy rows start at zero. A committed logical public mutation increments
once; private-only protection changes do not. Clients compare revisions, not
updated_at or bid sequence. Revision is server-managed and rejected in command input.

`/cable` accepts public `AuctionChannel` subscriptions with a valid existing positive
`auction_id`. There is no actor parameter or private maximum stream. The only domain
message is `{"type":"auction.changed.v1","auction_id":42,"revision":17}`.
It requests a fresh GET; it is neither a command acknowledgement nor a snapshot.
See [realtime](realtime.md) for ordering, privacy and missed-message recovery.
Phase 10 commits an internal public domain snapshot with each new outbox revision; the
wire message and command/REST response contracts are unchanged. A hint can be
delayed or duplicated and never confirms a command result.

## Phase 11 eventual public state

`GET /api/v1/auctions/:id/public-state` returns `{"data": {...}, "meta": {...}}`
with `Cache-Control: no-store`. `data` contains the auction ID, public revision,
currency and the Kafka v1 public snapshot fields: title, description, starting
price, minimum increment, status, current price, current leader ID, original/end
times, closed time and winner ID. It omits bid history, `created_at` and
`updated_at`. It never includes private maximum, priority, origin or key data.

When a valid Redis projection exists, `meta.source` is `redis` and metadata
includes `event_occurred_at`, `projected_at` and nonnegative `age_seconds`
(elapsed time since the event, not a freshness guarantee). Redis can lag
PostgreSQL indefinitely. On key miss, invalid value or Redis connection error,
the endpoint reads PostgreSQL and returns `meta.source=postgresql`,
`observed_at` and `age_seconds=0`. That zero describes the fallback observation;
it does not certify a cross-request snapshot. The ordinary `/auctions/:id` GET
always reads PostgreSQL and remains the correct recovery path for browser
commands and Cable hints. See [ADR-012](adr/012-redis-public-projection.md).
