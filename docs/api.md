# Phase 1 API

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
| POST | /auctions/:id/close | Close an active auction at/after ends_at |
| POST | /auctions/:id/cancel | Cancel an eligible auction with no bids |
| GET | /auctions/:auction_id/bids | List accepted bid history |
| POST | /auctions/:auction_id/bids | Place a sequential manual bid |

Create returns 201; reads, edits, and lifecycle actions return 200. Single resources
use `{"data": {...}}`. Lists use `{"data": [...], "meta": {"next_after_id": null}}`.
Lists are ordered by ascending ID, default limit 20, maximum 100. Pass positive
`limit` and optional `after_id`; follow next_after_id until null. These cursors do
not imply authoritative transaction ordering.

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
current_price, minimum_increment, starts_at, ends_at, current_leader_id, winner_id,
created_at, updated_at. Datetimes are UTC ISO 8601. No model internals are dumped.
Lifecycle actions take no body and never accept client time as authoritative.

## Bid input and representation

```json
{"bid":{"bidder_id":1,"amount":10500}}
```

The bidder must already exist. Money must be an integer JSON number: `10500.5`,
`10500.0`, and `"10500"` are invalid. A bid must meet starting_price if first;
otherwise current_price + minimum_increment. Responses contain id, auction_id,
bidder_id, amount, currency, created_at. There is no bid edit/delete API, rejected
bid table, idempotency key, or automatic bidding endpoint.

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
| 422 | auction_not_open | Active status but outside bidding window |
| 422 | bid_too_low | Amount below required minimum |

These are expected-error mappings, not a catch-all that hides programming failures.
No expected response includes exception class, SQL text, or a stack trace. Arbitrary
unknown routes still follow Rails routing behavior. Retrying a bid is not deduplicated.

## Run the live demonstration

From the root, after Compose is healthy:

```sh
./scripts/smoke-api
# Or run with the container's Ruby:
docker compose exec -T -e API_BASE_URL=http://127.0.0.1:3000 api ruby < scripts/smoke-api
```

The script creates a labelled user and auction, edits/schedules/activates it, accepts
two bids, rejects a low bid, waits about eight seconds for ends_at, closes twice,
rejects a post-close bid, and verifies history/leader/winner. It leaves those rows
for inspection. This is sequential HTTP verification, not a concurrency benchmark.
