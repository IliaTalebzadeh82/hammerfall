# Phase 21 — Marketplace trust and auction policy

Status: Phase 21 complete. Local and hosted API/web/Compose gates passed.
Phase 22 has not started.

## Stepped increments

Hammerfall chooses an opt-in stepped schedule while existing auctions retain
their fixed increment. The auction row lock precedes the current-price band
selection. A stale browser minimum cannot authorize a bid. Proxy resolution
selects the counter increment at the losing bidder's newly visible amount and
caps the response at the winner's private ceiling. Equal ceilings preserve the
existing durable priority. Public responses carry the effective increment,
not the private bidding instruction. See [ADR-018](../adr/018-stepped-bid-increments.md)
and the [Session 1 research/evidence](phase-21-session-1.md).

## Hidden reserve

The owner/operator may configure a nullable private integer-cent reserve while
draft. Scheduling freezes it. Valid manual bids below reserve remain accepted;
maxima advance toward the reserve without exceeding their ceilings or bypassing
proxy competition. Public state exposes only `none`, `not_met` or `met`.
An unmet close retains the highest bidder as `current_leader_id` but has no sale
winner. Met/unreserved closure assigns the settled leader as winner. SQL,
reconciliation and the public snapshot validate that distinction. See
[ADR-019](../adr/019-hidden-reserve-policy.md) and [Session 2](phase-21-session-2.md).

## Rapid closing

`closing_policy=regular|rapid` is persisted, defaults to regular for historical
and new rows, and freezes after draft. `ClosingPolicy` supplies the existing
`AuctionDeadline` arithmetic: regular final-60/+90; rapid final-15/+10. The
window includes exactly 15 seconds, excludes equality with `ends_at`, and adds
to the previous effective deadline. The same manual/maximum entry points lock
the auction and then read PostgreSQL `clock_timestamp()` before resolving
legality and extension. One accepted external commitment extends once, even
when it generates several proxy rows. New qualifying commands may extend again;
rejected commands, same-value maxima and historical replays do not.

Independent PostgreSQL connection tests force both serializations: a qualifying
bid holding the lock extends before the closer rechecks; a closer that finalizes
first makes the waiting bid reject. The browser displays the persisted mode and
refreshes the effective deadline from REST after command completion or Cable
invalidation. It does not calculate authoritative extensions. See
[ADR-020](../adr/020-auction-closing-policies.md).

## Combined scenario and failure behavior

The live Compose smoke creates a stepped, rapid auction with a €500 reserve.
A's €700 maximum establishes a €500 visible price. B's late €600 maximum
leaves A leading at €650 and extends exactly 10 seconds. The accepted command
passes through replica A, is read through B, and replays through B with the
same saved body and no additional extension. The committed revision reaches
the outbox, real Kafka audit consumer and Redis projection. The autonomous closer
retains A as leader and winner at €650 with the same extended deadline. Deleting the
projection and reconciling from PostgreSQL reproduces the exact public fields.
Final local evidence: auction 771, closed revision 5; executable
`apps/api/script/phase21_final.rb`, also run by the Compose CI job.

The real browser scenario first shows reserve not met, submits A's maximum,
shows reserve met, observes B's late challenge via Cable/REST, renders the
extended deadline, €650 price and €700 next minimum, then observes the settled winner after the
autonomous closer runs. Existing browser scenarios cover lost-response retry,
stale rejection, authenticated access and empty closure.

The complete local browser run passed 9 scenarios in 8.5 minutes with one
historical opt-in worker-outage scenario skipped. API/Kafka smoke and the
closer/reconciliation one-shots also passed after a successful Compose rebuild.

PostgreSQL remains authoritative during transport failure. An accepted command
with a lost response replays its historical result; a fresh GET supplies current
state. Outbox publication and projection delivery remain eventual. No FIFO lock
order or exact scheduler timing is claimed.

## Snapshot compatibility and rollout

Public snapshots remain schema v2. The validator accepts the exact early-v2
field set or that set plus a valid closing policy; unknown/private fields are
rejected. Retained v1 events remain historical unreserved/regular snapshots;
early v2 events normalize as regular. Earlier Redis v2 values are read as regular
after validating their original digest. An equivalent equal-revision event can
atomically add the default policy without a false digest conflict; different
data still conflicts. New snapshots and PostgreSQL rebuilds carry the policy.
Cable stays `auction.changed.v1` and contains only an invalidation hint.

Migrate PostgreSQL and deploy compatible readers, drain old writers/consumers,
then enable policy writers. Restart long-lived workers so they load the new
validator and policy. Rollback refuses rapid auction rows or outbox data containing
the new field; safe empty-data rollback/reapply was verified. No live cloud
rollout is claimed.

## Public behavior, approximation and inference

Catawiki publicly documents price bands, private maximum bidding, reserve
behavior and regular/Live closing windows; the dated first-party links are in
[Session 1](phase-21-session-1.md). Hammerfall chooses an explicit per-auction
policy, integer EUR cents, draft-only reserve/policy configuration and the
documented 60/90 and 15/10 timing effects. The locked resolver, database clock,
outbox, Kafka and Redis design are Hammerfall engineering choices. The €650
combined result is an engineering inference tested against Hammerfall's chosen
rules. Nothing here asserts Catawiki's internal architecture.

## Definition of Done review

| Phase requirement | Implemented / decision | Verification / evidence | Limit |
|---|---|---|---|
| Research current public policies and select two or three | Session 1 selected increments, reserve, rapid | First-party source inventory, ADR-018/019/020 | Public behavior only |
| Rule → invariant → concurrency → retry → API/UI → tests | All three documented and implemented | This report, invariants, focused model/request/race specs | SQL bypass writers outside workflow |
| Preserve PostgreSQL ordering and idempotency | Existing locks, post-lock clock and saved response ownership retained | Full backend regression, race seeds, replica smoke | No lock fairness guarantee |
| Marketplace trust and identity boundary | Seller self-bid covered by Phase 20 | Existing security regression | Account/country/category and payment rules deferred |
| Experiment go/no-go with privacy semantics | Rejected for this phase | Session 1 reasoned scope decision | No product analytics experiment |
| Real contention/retry/failure evidence | Independent connections, lost-response replay, live Kafka/Redis and browser | ExecPlan Evidence Index | Opt-in historic chaos tests remain separately selectable |
| Explain approximations and update public contracts | ADRs, API, domain/deadline/frontend/event/projection docs updated | Final documentation review | No exact Catawiki internals claim |
| Phase boundary | Phase 22 has not started | Changed-file and scope review | No durability/release phase work |

## Adversarial review

No unresolved Critical/High finding has been identified in the implemented
policy paths. The review checked that request bodies cannot choose a closing
mode per bid; rejected and replayed commands cannot extend; proxy row count
cannot multiply extension; the DB clock follows the row lock; closer/bidder
outcomes serialize; reserve winner semantics remain SQL-enforced; private
reserve/maximum/priority stay outside public snapshots; retained events default
to regular; Redis and browser countdowns do not decide auction state; stepped
competition respects ceilings and equal-ceiling priority.

Medium, fixed: Session 2 Redis v2 entries lacked the new field, causing a
potential equal-revision digest conflict during replay. Original-digest
validation plus equivalent regular normalization handles that upgrade without
accepting unrelated conflicting data. Low, fixed: existing local Compose roles
had pending Phase 21 migrations and stale long-lived workers; migrations and
role restart restored the current implementation. Informational: local timing,
single PostgreSQL authority and eventual public delivery retain their existing
operational limits.

## Verification and accepted limits

Final local results: 554 backend examples, 0 failures, 4 opt-in pending (seed
33589); 78 frontend tests plus typecheck/lint/format/build; 9 browser scenarios,
1 historical opt-in skipped; five rapid race seeds with 3 examples each;
RuboCop 173 files/0 offenses, Zeitwerk, Brakeman and bundler-audit passed.
Migration rollback/reapply and both populated-data downgrade guards passed.
Hosted [run 37268740679](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37268740679)
completed successfully on implementation SHA
`7da69bc1724710548f6db636b8e02392ba1ade1d`. Its API RSpec, web tests/build,
Compose combined policy smoke and real browser steps completed successfully.
The [ExecPlan](../plans/phase-21-execplan.md) records commands and live records.
Session 1/2 evidence remains preserved. No Critical or
High finding remains unresolved in the final adversarial review.
Active reserve lowering/removal, seller management UI, payment/bid reservations,
country/category restrictions, livestream/video/chat and live cloud deployment
are excluded. Rapid closing models deadline behavior only. Public price action
may reveal that a reserve threshold has been reached, while the configured raw
field remains private.
