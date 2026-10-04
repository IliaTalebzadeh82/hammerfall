# ADR-020 — Persisted auction closing policy

Status: Design selected in Phase 21 Session 1; implementation and races pending.

## Context and public behavior

Catawiki [regular closing help](https://www.catawiki.com/en/help/bidding-basics/why-are-bidding-times-for-some-lots-occasionally-made-longer) documents a bid within the last 60 seconds adding 90 seconds. Its [Live buyer policy](https://www.catawiki.com/en/help/policies-guidelines/catawiki-live-buyer-policy) documents valid bids in the last 15 seconds adding 10 seconds, including repeat extensions, through the same official bidding system. Stream and chat statements are not bids. Hammerfall already implements final-60/+90 under the auction lock and PostgreSQL time.

## Hammerfall decision

Persist an immutable-after-draft `closing_policy` of `regular` or `rapid`, defaulting existing rows to `regular`. `regular` preserves 60/90. `rapid` models only 15/10, without stream, chat, presentation order or distinct bid transport. A small `ClosingPolicy` domain concept supplies window and extension to the existing `AuctionDeadline` arithmetic; both policy values still use `place_bid!`, `set_maximum!`, the auction row lock, `AuctionClock.now` after lock acquisition, and the same closer. Accepted external commitments extend once; generated proxy rows and replays do not. Eligibility remains `starts_at <= decision_time < ends_at`, so equality with end is closed. Repeated qualifying commands may extend again.

Expose the mode and current deadline in public API and snapshot so a bidder can understand the shorter response window. The mode has no authority outside PostgreSQL. Combined with reserve, rapid closing may end unsold or sold according to the settled visible bid at finalization.

## Alternatives

- Build a separate Live bidding path or streaming state: duplicates auction authority and risks two winners.
- Read the mode from request headers or browser state: lets clients select deadlines and breaks retries.
- Hardcode scattered `if rapid` branches: obscures the invariant and invites different behavior in bid versus maximum paths.

## Consequences, risks and revisit condition

The public snapshot schema and frontend need a compatibility rollout alongside reserve status. Boundary and bid-versus-closer tests must use real PostgreSQL time/locks, including exactly 15 seconds, exactly end, repeated extensions and both lock orders. The faster window makes latency operationally relevant but does not change bid legality authority. Revisit when a genuine Live product has additional scheduling or interface requirements.
