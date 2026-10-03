# Phase 23 — Catawiki Case Study & Demo

Status: Planned; begin only on explicit request

## Goal

Make the engineering repository understandable and evaluable by a Catawiki engineer in roughly ten minutes. Convert accumulated work into a clear story, retained evidence, a reliable demo and honest trade-off discussion. This is primarily communication and evidence work, not a feature phase.

## Deliverables

1. A 60-second explanation of what Hammerfall is and why it was built: an auction-marketplace study of correctness and resilience under contention and failure.
2. A 10–15 minute walkthrough usable in an engineering call: auction command → PostgreSQL authority → concurrency/ordering → idempotency → outbox → Kafka → projection → realtime → failure/recovery. Avoid a directory-by-directory tour.
3. Roughly three flagship experiments selected from real retained evidence. Strong candidates are final-second concurrent bidding; committed command, lost HTTP response and idempotent retry; and duplicate/reordered async delivery with reconciliation. Reproduce or clearly qualify evidence where needed.
4. One primary architecture diagram that clearly marks authoritative, derived, transport, orchestration and cloud boundaries.
5. An engineering case study organized by problem, naive solution and failure, Hammerfall decision, alternatives, experiment, actual result and remaining limit rather than by roadmap phase.
6. A Catawiki alignment section separating publicly evidenced technologies/domain behavior from Hammerfall-specific architectural choices. Refresh public-source research at kickoff and never imply internal knowledge.
7. A grounded “what I would change at real Catawiki scale” discussion of possible service boundaries, hot-auction contention, database topology, event infrastructure, capacity and organizational ownership. Do not claim these changes are automatically required.
8. Interview/conversation prompts on hot auctions, authority/ordering, bidding-service boundaries and ambiguous command recovery, aimed at substantive engineering discussion.
9. A simple reproducible demo, preferably a single script or runbook for local showcase startup, requiring no paid GCP resources.

## Success and boundary

A technically experienced engineer unfamiliar with Hammerfall can grasp why it exists, its three hardest problems, evidence, major trade-offs and remaining limits in about ten minutes. Claims cite actual tests, experiments or public sources; no invented Catawiki internals or production guarantees. Update progress and handoff. Do not start Phase 24 without an explicit request.
