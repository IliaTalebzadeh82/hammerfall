# Frontend — through Phase 20 Session 1

Hammerfall is a text-focused auction interface backed entirely by Rails. It uses
Next.js App Router, React, TypeScript, Tailwind v4 and shadcn Base UI primitives.
The listing is `/auctions`; `/` redirects there; detail is `/auctions/[id]`.
The shell, login/logout control, collection cards, public history, bidding forms,
loading/error/empty states and mobile layout form the complete current product.
There are no invented media, seller, payment or account features.

## Data and authority

One typed API module uses same-origin `/api/v1` calls through a configured transport
rewrite. Runtime guards validate required public fields and safe numeric IDs/money;
components render explicit allowlists. Cursor pagination is visible through Load
more controls. Bid history follows increasing sequence, including equal-price rows,
not client timestamps. On refresh, loaded history resets to its earliest page.
No union of independent requests claims snapshot consistency.

GET state supplies price, current_leader_id, winner_id, effective/original deadlines
and lifecycle status. Accepted commands never imply leadership. An active leader
is never labelled winner. Draft/scheduled/cancelled/closed disable new bidding;
expired-looking active state shows Checking status and asks Rails again. The browser
never submits a close command or declares closure itself.

## Intentions and recovery

Each explicit submission creates one opaque UUID and immutable operation/auction/
actor/amount payload. The shared session saves it before sending, blocks duplicate
clicks and both forms, and retains it across navigation/reload after
an uncertain outcome. Retry safely uses the same key and payload, including after
closure. Refreshing public state alone cannot resolve an unknown command outcome.
Abandonment requires an explicit warning step and does not cancel server work.

Success or valid terminal 400/404/409/422 clears the saved record and refreshes
auction plus history. Idempotency-Replayed recovers the previous result, followed
by those fresh reads. A 409 never generates another key automatically. Known
errors explain low bids, binding maximum decreases, noncompetitive maxima, deadlines,
invalid state, seller self-bid, missing auction and validation problems. Historical minimum/
price error details are labelled as values at that decision. Network failures,
timeouts/abort, malformed responses, 401 and 5xx preserve the intention. A 401
requires reauthentication as the original actor before same-key retry. No mutating request
has an automatic retry loop.

The per-tab retry horizon is one hour. It is intentionally shorter than the backend
minimum retention setting, but cannot protect against manual database deletion or
lost browser storage. Session storage holds only an unresolved command; for a maximum
this temporarily contains that actor's private submitted amount. It is never logged
or put into localStorage. A resolved maximum acknowledgement does not create a
persistent display of the actor's current protection, because the API does not
provide that state. Signing out clears unsubmitted form inputs. The actor ID
stored with a pending intention only prevents a different signed-in user from
retrying it; the server derives command identity from its HttpOnly session cookie.

## Time, money and accessibility

`X-Server-Time` estimates an app-server/browser offset for countdown display. The
post-lock PostgreSQL clock still decides legality. At zero, one refresh per ends_at
is triggered. Explicit refresh, tab visibility return and terminal commands also
refresh; Cable invalidations and subscription confirmations also refresh.
Updated ends_at resets the countdown.
A delayed closer can leave Checking status visible until the next refresh.

Money inputs are strings, parsed as bounded integer EUR cents. Decimal point/comma
are accepted; fractional cents, signs, exponent/grouping formats and non-positive
values are rejected without rounding. Display uses en-IE EUR formatting, while
timestamps use the browser timezone. The next manual minimum is a convenience only.

The UI uses real labels, described errors, live regions for command outcomes,
visible focus, semantic table headings, textual state badges, a skip link and
reduced-motion support. The countdown is not a per-second live-region announcement.
Desktop uses a summary/form split; mobile stacks them and provides a direct bidding
anchor. Inline abandonment confirmation introduces no modal focus trap. Long titles
wrap; history has a contained horizontal scroll area when needed. No formal WCAG
certification or exhaustive assistive-technology coverage is claimed.

## Verification

Vitest/Testing Library cover money, public data validation, clocks, sequence paging,
revision-based stale-read rejection, refresh coalescing, empty/not-found states,
privacy, immutable retries, reload
recovery, terminal refresh, errors, actor switching and storage failure. Playwright
uses the real running API for browsing, user selection, bids/maxima, stale rejection,
a real committed response deliberately dropped before safe recovery, closing, and
390/768/1440 layouts with long titles and large prices. See progress.md for actual
results, installed-browser fallback and screenshots inspected.

Phase 7 adds actual server-pushed invalidations and reconnect recovery while
preserving these client command guarantees. See [realtime](realtime.md) and ADR-008.
Connection status is separate from REST errors and command state; disconnected
clients can still bid. One owned consumer is cleaned up on detail unmount. Listing
pages retain explicit REST refresh and do not open auction subscriptions.
