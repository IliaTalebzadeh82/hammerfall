# Phase 21 — Marketplace Trust & Auction Policy

Status: Complete — local and hosted API/web/Compose gates passed on implementation SHA `7da69bc1724710548f6db636b8e02392ba1ade1d` ([run 37268740679](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37268740679)); Phase 22 has not started

## Goal

Study a small number of real auction-marketplace policies that create worthwhile correctness, identity, fraud/trust or concurrency questions. Strengthen Hammerfall as a Catawiki-aligned case study, without building a complete Catawiki clone.

## Research and selection

At kickoff, research current public Catawiki sources. Clearly separate publicly documented behavior, Hammerfall's approximation/design, and engineering inference; never claim access to Catawiki internals. Investigate minimum bid increments, reserve price, seller self-bidding, bidder/account eligibility, closing rules and proxy/maximum bidding rules. Select only two or three policies by learning value around correctness, concurrency, identity, fraud/trust, ordering, privacy and failure behavior. Minimum increments, reserve price and seller/eligibility restrictions are hypotheses, not commitments. Consider a Catawiki Live-like alternate deadline only if current public evidence and engineering value justify it.

For each adopted policy, document business rule → invariant → concurrency interaction → failure/retry interaction → API/UI contract → tests → evidence, including why the rule matters to an auction marketplace. Preserve PostgreSQL authority and established ordering/idempotency guarantees unless an explicit reviewed ADR supplies equivalent guarantees. Do not implement every discovered feature.

The originally unscheduled lightweight product experiment belongs here for an explicit go/no-go decision: consider stable actor/experiment bucketing, a compact bidding-panel variant and exposure/start/submission/acceptance/win events only if useful to a selected policy or case-study question. Define consent/privacy, identity linkage, retention and event meaning first. Distinguish product analytics from Phase 13 operational telemetry and auction domain events. Record a reasoned decision even if the experiment is omitted; never treat the old example as automatic scope.

## Verification and boundary

Use tests that exercise policy invariants and relevant contention/retry/failure paths, and retain real evidence. Update public contracts and explain approximations and limits. Marketplace policy belongs here; identity fundamentals belong to Phase 20. Do not start Phase 22 without an explicit request.
