# Phase 5 API

Base path: `/api/v1`. This API is for local development. There is **no authentication
or authorization**; supplied bidder_id identifies a database row, not the caller.
Use JSON request bodies with Content-Type: application/json. See
[domain semantics](domain-model.md) for lifecycle and money rules.

## Endpoints

| Method | Path | Behavior |
| --- | --- | --- |
| GET | /users | List minimal user identities |
| POST | /users | Create identity from `{"user":{"name":"Alice"}}` |
| GET | /auctions | List auctions |
| POST | /auctions | Create a draft |
| GET | /auctions/:id | Read one auction |
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
{"bid":{"bidder_id":1,"amount":10500}}
```

The bidder must already exist. Money must be an integer JSON number: `10500.5`,
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
| 404 | user_not_found | Bidder ID does not exist |
| 422 | validation_failed | Model fields are invalid; details maps field names to message arrays |
| 422 | invalid_state_transition | Edge or transition precondition is invalid |
| 422 | invalid_auction_state | Bid on non-active auction or edit outside draft |
| 422 | auction_not_open | Active status before starts_at |
| 422 | auction_ended | Active status but DB decision time at/after ends_at; details includes public ends_at |
| 422 | bid_too_low | Amount below required minimum |

These are expected-error mappings, not a catch-all that hides programming failures.
No expected response includes exception class, SQL text, or a stack trace. Arbitrary
unknown routes still follow Rails routing behavior. Matching retained keys replay; a fresh key is a new logical command.

## Run the live demonstration

From the root, after Compose is healthy:

```sh
./scripts/smoke-api
# Or run with the container's Ruby:
docker compose exec -T -e API_BASE_URL=http://127.0.0.1:3000 api ruby < scripts/smoke-api
```

The script creates a labelled user and auction, edits/schedules/activates it, accepts
two bids, rejects a low bid, waits about 65 seconds for ends_at, closes twice,
rejects a post-close bid, and verifies history/leader/winner. It leaves those rows
for inspection. This is sequential HTTP verification, not a concurrency benchmark.


For simultaneous HTTP verification, run `./scripts/smoke-concurrent-bids`. It starts
12 concurrent increasing attempts and eight equal-amount attempts on two fresh
auctions, verifies accepted history/sequences/price/leader and prints outcomes.
Rows remain labelled for inspection. Optional API_BASE_URLS is a comma-separated
list of running Rails URLs for routing requests across independent processes.
This is correctness smoke coverage, not a capacity benchmark.


## Private maximum configuration

PUT `/api/v1/auctions/:id/maximum-bid`:

```json
{"maximum_bid":{"bidder_id":42,"maximum_amount":50000}}
```

Returns 200 for create, increase or same-value no-op:

```json
{"data":{"auction_id":1,"bidder_id":42,"accepted":true}}
```

The acknowledgement intentionally omits even the supplied ceiling and private
priority. No GET/list/delete maximum endpoints exist (404). Unknown fields such as
priority_sequence/origin are 400. Supplied bidder_id is still a demo actor selector,
not authentication: representation privacy does not prevent impersonation/probing.

Money uses the same strict bounded integer cents validator. New or increased protection covers
starting_price, or exceeds public current_price for a nonleader, or covers the
current leader's own visible price. Partial final increments are allowed for
proxies. A nonleader increase at/below public price is rejected as
maximum_bid_too_low without changing private state or priority. Same amount
preserves priority; a valid increase resets it.

Additional 422 errors: maximum_bid_cannot_decrease and maximum_bid_too_low. They
contain no stored private amount. The latter may contain public current_price.
Existing validation_failed/invalid_auction_state/auction_not_open/user_not_found
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

{"bid":{"bidder_id":9,"amount":25000}}
```

Use a fresh key for each new intention and **reuse the same key and semantic payload
when retrying an uncertain outcome**. Keys are opaque, case-sensitive, 1–255 visible
ASCII characters, without spaces or control characters. UUID is allowed, not required.
The scope is actor + operation + key; actor is still an unauthenticated supplied
user ID. An actor may use the same key independently for bid and max commands.
Reusing it for another auction or amount within one operation is a conflict.

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

All existing smoke scripts now generate a new key per distinct bidding command.
`scripts/smoke-idempotency` reuses keys intentionally across two independent API
URLs to demonstrate duplicates, conflicts, lost responses and replay after closure.
