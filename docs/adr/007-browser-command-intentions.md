# ADR-007: A request/response frontend with durable pending intentions

Status: Accepted — Phase 6, 2026-09-26

## Context

The backend already serializes bidding, resolves private maxima, extends deadlines,
and retains idempotent outcomes. A browser can still show an old price, lose a
committed response, or incorrectly label an accepted bidder as leader. Phase 6
must expose the real engine without moving authority into TypeScript or introducing
Phase 7 event delivery.

## Decision

Use App Router route components with a consistent client-side REST layer. `/`
redirects to `/auctions`; `/auctions/[id]` validates the route ID and renders the
interactive detail view. No Server Actions, Next API route handlers or BFF business
logic. Next's configured rewrite transparently forwards `/api/v1/*` to Rails;
`API_ORIGIN` defaults to native loopback and Compose sets `http://api:3000`.
Rails development Host Authorization allows only the additional `api` hostname;
Next dev origins explicitly permit loopback. This does not broaden production CORS.

`lib/api/client.ts` owns fetch, bounded command timeout, runtime shape guards,
public types, cursor pagination, metadata and error translation. Responses retain
status, Headers and parsed body. Public views explicitly select fields; they never
render whole objects or private metadata. Runtime guards reject malformed success
responses; command transport errors, invalid JSON, unexpected shapes and 5xx are
conservatively ambiguous. Safe JSON 400/404/409/422 responses are terminal rejections.
No mutation automatically retries, and no price/leader is optimistically updated.

Shared context contains demo actor selection and one unresolved intention per tab;
list/detail/read state stays local. Actor selection is visibly unauthenticated and
persists only an ID in localStorage. Users come from the real paginated endpoint.
Public bidder names fall back to `Bidder #ID` when that user's page is not loaded.

An intention freezes opaque crypto.randomUUID key, operation, auction ID, actor ID,
integer amount and creation time on submit. A synchronous in-flight guard prevents
rapid double submission before React rerenders. The intention is written to
sessionStorage **before** transmission. Storage failure blocks transmission rather
than risking an unrecoverable reload. Both forms and actor switching are locked
while unresolved. The browser can retry that same intention even when fresh GET
state now says closed. New commands remain unavailable on closed/cancelled/draft/
scheduled pages.

On valid terminal response, remove the pending record and refresh both auction and
history. Replay is recognized as recovery of a historical result, not fresh state.
On ambiguity, keep the exact key/payload and offer explicit safe retry, public-state
refresh, or a two-step inline abandonment warning. Abandonment cannot cancel a
committed bid. A different intention receives a new key. A per-tab global banner
keeps the unresolved command discoverable across route changes and reloads. Pending
maxima exist temporarily in that actor's session storage; they are not public
history, logged, copied to URLs, or retained as a confirmed-maximum display.

The client safe-retry horizon is conservatively one hour, below the backend's
minimum configurable one-day retention. Beyond it (or after an observed backward
wall-clock change), offer review/abandonment instead of transmitting. This is a
client safeguard, not a new server retention guarantee. Manual privileged pruning,
clock changes, lost browser storage and copied browser tabs remain limitations.

## Presentation clock and refresh

API BaseController adds `X-Server-Time` with application UTC wall time on normal
responses and expected error renders. It is fresh transport metadata, never part
of the stored Phase 5 snapshot or bidding decision. The browser estimates offset
as parsed header time minus its clock when the response arrives. This does not
reproduce PostgreSQL clock_timestamp(): network delay, app/DB skew and clock changes
can affect display. Missing metadata falls back to the local clock with the same
visible estimate disclaimer.

An isolated countdown ticks locally. At zero, show Checking status and trigger one
GET refresh per observed effective deadline; never locally close or select a winner.
A new ends_at resets presentation. Refresh also occurs explicitly, after terminal
commands, and on returning to a visible tab. There is no polling loop, WebSocket,
SSE, subscription or realtime indicator. If a closer lags past the zero-triggered
read, the page remains Checking status until another refresh. Reads use abort and
generation guards so stale completions cannot overwrite later responses. Auction
and history GETs still need not describe one PostgreSQL snapshot.

## Money

Parse bounded decimal strings into integer cents using digit groups, never
parseFloat multiplication. Support decimal point or comma, at most two places,
no grouping/exponents/signs, and the backend 1..1e12-cent range. All comparison and
payload values remain integers. Intl.NumberFormat formats display-only euros.
Displayed manual minimum is a hint; server rejection and fresh GET state prevail.

## Alternatives considered

- Optimistic price/leader: claims acceptance or leadership before the authoritative
  proxy contest finishes; deliberately rejected.
- New key per retry: turns a lost response into another business command.
- Component-only pending state: navigation/reload loses the retry identity.
- localStorage command history: unnecessarily retains private submitted maxima
  across browser sessions. Use only sessionStorage for the unresolved command.
- Redux/GraphQL/BFF: no demonstrated need beyond local state plus one context.
- Broad CORS: unnecessary with a transparent same-origin rewrite.
- Aggressive polling or simulated realtime: obscures stale-state behavior and
  duplicates future Phase 7 work.

## Consequences and risks

Clients explicitly distinguish command outcome from current state. Safe retry
survives tab reload while storage is retained. No frontend state authorizes bidding.
This is still an unauthenticated local demo, without authorization-based maximum
secrecy or cross-tab coordination. sessionStorage contains the caller's own pending
maximum until resolution/abandonment/tab cleanup. Duplicating a tab can copy its
intention; server idempotency still protects a matching retained key. Forms have
inline binding-commitment copy rather than a mandatory modal for every bid.

## Revisit when

Phase 7 adds server-pushed updates and reconnect handling. Preserve this command
identity boundary, explicit winner/leader distinction and refresh-after-command
behavior; do not treat event delivery as proof of a command's result. Review API
state/version ordering, clocks, authentication-derived actor scope, session retention,
and accessible update announcements before connecting event streams.
