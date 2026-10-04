# Phase 21 ExecPlan — Marketplace trust and auction policy

Status: In progress; Session 1 increment milestone complete, checkpoint ready.
Current milestone: Session 1 documentation, commit and checkpoint.
Completed: First-party public research and policy gate; [Session 1 report](../marketplace/phase-21-session-1.md); [ADR-018](../adr/018-stepped-bid-increments.md), [ADR-019](../adr/019-hidden-reserve-policy.md), [ADR-020](../adr/020-auction-closing-policies.md); opt-in stepped increment migration, locked manual/proxy implementation, API/async effective-increment representation, focused tests and relevant contract docs.
Verified: Migration on local PostgreSQL test DB; 95 focused examples/0 failures; 264 wider affected backend examples/0 failures/1 preexisting live-Kafka opt-in pending; 20 isolated Redis projection/reconciliation examples/0 failures; RuboCop 9 changed Ruby files/0 offenses. See Evidence Index.
Remaining: Implement private reserve and rapid closing policy; combined contention/retry/privacy, snapshot schema rollout, frontend, real multi-instance/Compose/Kafka/Redis proof, full regression, browser, adversarial review, hosted CI, final docs and Phase 21 completion. Do not start Phase 22.
Known failures/limitations: Initial wider test run on shared local Redis DB had 14 projection/reconciliation failures from stale keys with reused test auction IDs; rerun on empty DB 15 passed. No product defect inferred. Stepped `minimum_increment` create input remains required for compatibility but is ignored by pricing. No live infrastructure or full Phase 21 gate yet.
Relevant files: `apps/api/app/models/auction.rb`, `apps/api/app/models/bidding/bid_increment_policy.rb`, `apps/api/app/models/bidding/proxy_resolver.rb`, `apps/api/app/models/auction_deadline.rb`, public snapshot/presenter, bidding/request/concurrency specs.
Relevant ADRs: [ADR-003](../adr/003-auction-concurrency-control.md), [ADR-004](../adr/004-proxy-bidding.md), [ADR-005](../adr/005-auction-deadlines-and-soft-close.md), [ADR-016](../adr/016-first-party-identity-and-sessions.md), [ADR-018](../adr/018-stepped-bid-increments.md), [ADR-019](../adr/019-hidden-reserve-policy.md), [ADR-020](../adr/020-auction-closing-policies.md).
Next-session starting point: Read this plan and [latest handoff](../handoffs/latest.md), then implement reserve from ADR-019. Update SQL closed-winner check and public snapshot contract atomically with private-state tests. Implement rapid closing from ADR-020 after reserve milestone; do not start Phase 22.

## Decisions

- ADOPT price band increments, private reserve, and a rapid closing policy. Each has a direct locked-state or deadline invariant and first-party public evidence. Implement only the increment slice in Session 1 if the combined work is substantial.
- SATISFIED BY PHASE 20: seller self-bid rejection, after the auction lock and authenticated actor resolution.
- DEFER account/country/category restrictions and bid reservations: meaningful versions require signals, payment holds, and rules absent from this case study.
- REJECT the lightweight bidding-panel experiment for Phase 21: it does not strengthen proof of auction policy and would require separate consent, retention and analytics semantics.
- Existing auctions retain their fixed increment. A new opt-in stepped schedule is a Hammerfall approximation of the current published Catawiki table; their help article warns that some lots differ due to experiments. Reserve and rapid closing designs will also be explicit Hammerfall approximations.

## Evidence Index

| Check | Command / method | Result | Evidence |
|---|---|---|---|
| Public rules | First-party Catawiki Help Centre and policy pages, 2026-10-04 | Captured | [Session 1 report](../marketplace/phase-21-session-1.md) |
| Migration | `RAILS_ENV=test bin/rails db:migrate` with local `.env` | Exit 0 | Added `increment_policy` default `fixed` and CHECK in test PostgreSQL |
| Initial focused backend | 5 affected model/request/concurrency specs | 95 examples, 0 failures | `/tmp/phase21-focused.log`, seed 52230 |
| Redis isolation diagnosis | 2 projection/reconciliation specs with `REDIS_URL=redis://127.0.0.1:6379/15` | 20 examples, 0 failures | `/tmp/phase21-projection-isolated.log`, seed 41380; shared DB 0 had stale test-ID keys |
| Wider affected backend | 14 model/request/integration specs, isolated Redis DB 15, pool 15 | 264 examples, 0 failures, 1 pending | `/tmp/phase21-broad-focused-isolated.log`, seed 11240; pending is opt-in live Kafka |
| Final changed tests | Increment, idempotency, concurrent-bidding specs after test additions | 36 examples, 0 failures | `/tmp/phase21-final-focused.log`, seed 6380 |
| Repeated increment race | `rspec spec/integration/concurrent_bidding_spec.rb:68 --seed N`, N=1..5 | 5 runs × 1 example, 0 failures | `/tmp/phase21-race-1.log` through `-5.log`; both serial outcomes permitted |
| Ruby lint | `bundle exec rubocop` on 9 changed Ruby files | 9 inspected, 0 offenses | `/tmp/phase21-rubocop.log` |
| Diff check | `git diff --check` | Exit 0 | No whitespace errors |
