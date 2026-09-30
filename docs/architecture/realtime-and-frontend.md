# Frontend and realtime observation

## Current flow

The Next.js App Router UI lists auctions, shows detail/history, and sends manual or private-maximum commands through a same-origin `/api/v1` rewrite to Rails. Rails REST is the current public view. The browser parses decimal EUR input into bounded integer cents, keeps price/leader/winner read-only from server state, and treats its countdown and `X-Server-Time` offset as estimates. A countdown reaching zero triggers a GET; it never closes an auction.

A per-tab pending intention saves operation, actor, auction, amount and UUID key in `sessionStorage` before transmission. Transport ambiguity preserves it for explicit retry; a terminal response resolves the original command, followed by fresh auction/history reads. Browser storage can be lost, and actor ID selection is only an unauthenticated demo. No optimistic price/leader changes or invented command success are permitted.

## Invalidation contract

Action Cable uses PostgreSQL LISTEN/NOTIFY across Rails processes. A public mutation increments `Auction.public_revision` once under the existing lock and schedules one post-outer-commit publication. Private-only changes, no-ops, rejection, replay and rollback do not publish. The sole message is `{type:"auction.changed.v1",auction_id,revision}`; it carries no price, bid, maximum, origin, key or command outcome. The browser fetches REST on confirmation/reconfirmation and higher revision hints, coalesces bursts, and refuses older REST revisions. Subscription recovery closes the initial GET/subscription gap and reconnect gap.

Delivery is best-effort. Commit followed by crash before broadcast can lose a hint; NOTIFY has no retained replay. A connected browser may remain stale until a later hint, manual/focus/command/countdown refresh or reconnect. Auction and bid-history GETs can straddle commits. A socket cannot prove database health or command outcome. See [ADR-007](../adr/007-browser-command-intentions.md), [ADR-008](../adr/008-realtime-auction-invalidations.md), [frontend](../frontend.md), [realtime](../realtime.md), and [API](../api.md).

## Later evolution

Phase 8 jobs do not automatically make event publication durable. Phases 9–12 add outbox, Kafka, Redis projections and reconciliation separately. Preserve public-only delivery, revision ordering, explicit freshness and REST recovery if the Cable adapter or read model changes. Test independent Rails processes and real disconnect/reconnect, not just the in-process adapter.
