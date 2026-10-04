# Phase 21 Session 2 — hidden reserve milestone

Date: 2026-10-04. Phase 21 remains active. This session implements
[ADR-019](../adr/019-hidden-reserve-policy.md); rapid closing remains pending.

## Reserve invariants and schema

`Auction.reserve_price` is nullable private integer EUR cents, from
`starting_price` through the established maximum. Null means no reserve;
historical rows remain null. The seller or operator can write it only through
draft create/edit. Scheduling freezes it permanently. An ordinary public GET,
including the seller's GET, exposes only `reserve_status` (`none`, `not_met`,
`met`). A reserved auction with no accepted bid is `not_met`, even if its
starting price equals reserve.

The auction lock and PostgreSQL decision clock still own eligibility, proxy
resolution, close and public revision/outbox. Manual bids below reserve are
accepted if they meet the normal increment. Automatic rows never exceed their
bidder's ceiling, price never decreases, and equal maxima keep durable
priority. Closing an unmet auction retains `current_leader_id` as highest
bidder with `winner_id=NULL`; a met or unreserved auction closes with the
leader as sale winner. SQL now enforces that conditional winner relation.
Duplicate close is unchanged. Migration rollback refuses to drop populated
reserve or v2 outbox data.

## Proxy examples

With start €100 and reserve €500: manual €200 stays visible/not met; a
€400 maximum becomes fully visible/not met; a €700 maximum first displays
€500/met. A leader at €300 raising to €450 displays €450/not met; raising
to €700 displays €500/met. With A at €700 and B at €600, A remains leader
at €650 under the €501–1,000 stepped band. A €620 ceiling against B's €600
uses the established partial counter at €620. Tests also cross the €100,
€200, €500 and €1,000 bands and cover fixed increments and equal ceilings.

## Privacy threat model

The raw amount is excluded by server allowlists from public auction/bid/max
responses, history, transactional outbox, Kafka, Redis, Cable and browser
state. Request/SQL parameter filtering covers the configured field; errors
contain only generic validation text or public bidding minimums. Bounded
reserve status is public. Observers may infer a threshold when a visible
bid crosses it or a proxy bid displays the reserve; that price action is an
intentional effect, not a raw configuration field. Database administrators
can inspect the column; no field encryption is claimed.

## Event/snapshot migration

**INTRODUCE v2.** The v1 domain event validator requires exact public keys
and leader/winner equality at close, so adding status to v1 would break its
contract. New outbox/Kafka domain events use `.v2` names and schema version
2. The unchanged `auction.changed.v1` Cable message remains only an
invalidation. Consumers accept retained v1 and new v2 envelopes; v1 data is
normalized to `reserve_status=none` when projected. Redis now uses a v2 key,
leaving old v1 keys ignored. Missing state falls back to PostgreSQL; bounded
reconciliation seeds current public status from PostgreSQL without copying
reserve. The existing Kafka topic/groups and their offsets remain. Rollout
requires database migration and new readers before reserve writers, with old
bid writers and consumers drained before v2 events are emitted.

## Evidence and limits

Focused model, API, SQL, idempotency, privacy, Kafka contract, Redis and
independent PostgreSQL contention tests cover the implemented invariant.
The affected backend selection passed 311 examples, 0 failures and 2 opt-in
pending checks on isolated Redis DB 15. Five reserve maximum race seeds passed;
33 frontend tests, typecheck, lint and build passed. Test migration,
rollback/reapply, Zeitwerk and RuboCop passed. Exact commands and logs are
indexed in the [ExecPlan](../plans/phase-21-execplan.md). A successful test run against local
PostgreSQL/isolated Redis proves those boundaries, not a live multi-instance
broker rollout. Active reserve edits, seller management UI, payment, offers
after unsold closure and rapid closing are deferred. No Phase 21 completion
claim is made.
