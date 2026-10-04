# Current handoff — Phase 21 Session 2 reserve checkpoint

Updated: 2026-10-04. Phase 20 is complete. Phase 21 Marketplace Trust &
Auction Policy remains active; Phase 22 has not started. Resume in a fresh
Codex conversation from the [ExecPlan](../plans/phase-21-execplan.md),
[Session 2 report](../marketplace/phase-21-session-2.md),
`docs/phases/phase-21.md` and [context map](../context-map.md).

Adopted policies are stepped minimum increments (implemented in Session 1),
hidden reserve (implemented in Session 2) and rapid closing (ADR-020 design,
pending). Seller self-bidding is already covered by Phase 20. Account/country/
category restrictions and payment reservations are deferred; the bidding-panel
experiment is rejected for this phase.

Reserve implementation: nullable private integer-cent `reserve_price` is
configured through owner/operator draft create/edit and freezes on scheduling.
Manual bids below reserve remain valid. The locked proxy resolver advances
maxima toward reserve without exceeding a bidder's ceiling or replacing
stepped competition/priority. Closing below reserve retains the highest
bidder in `current_leader_id` with no sale winner; SQL and PostgreSQL
reconciliation match this rule. Public `reserve_status` exposes only
`none`/`not_met`/`met`. New outbox/Kafka domain snapshots are v2; readers can
decode retained v1, and Redis uses a v2 key rebuilt from PostgreSQL. Cable
remains a v1 invalidation. Frontend list/detail show public reserve status.
See [ADR-019](../adr/019-hidden-reserve-policy.md).

Evidence: test PostgreSQL migrate/rollback/reapply; 311 affected backend
examples/0 failures/2 opt-in pending with Redis DB 15 and pool 15; 5
independent reserve race seeds/0 failures; 33 frontend tests, typecheck,
lint and build; 20 changed Ruby files linted/0 offenses; Zeitwerk passed.
Logs and commands are in the ExecPlan Evidence Index. No real broker or
multi-instance rollout, full Phase 21 suite, browser gate or hosted CI proof
is claimed. Active reserve edits, seller UI and payment/post-auction offers
remain deferred.

Next: implement rapid closing from [ADR-020](../adr/020-auction-closing-policies.md),
then combined reserve/rapid contention and the remaining live/final Phase 21
gates. Do not start Phase 22.
