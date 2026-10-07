# Phase 23 ExecPlan — case study and demo

Status: Active; Session 1 narrative/evidence milestone ready for checkpoint.
Current milestone: Session 1 documentation and evidence checkpoint.
Completed: First-party Catawiki refresh, claim/source registers, three flagship stories, primary Mermaid architecture diagram, case study, redesigned README, 60-second opening, timed walkthrough, interview guide, real-scale discussion, demo concept, code-map/learning/journal/progress/handoff updates.
Verified: Starting tree clean at `49c2140b94cc3cd3b5833ccf7609370fa728069b`; 304 local Markdown targets/anchors checked with 0 problems; prose claim-word scan reviewed; code fences balanced. Final staged whitespace and Git checks below.
Remaining: Session 2 builds and verifies the reproducible showcase, audits all links/citations/claims on the final document set, performs a timed reader test and warranted regression, then closes Phase 23.
Known failures/limitations: No product code changed or product suite rerun. Mermaid CLI was unavailable; two compact diagrams were syntax-inspected only. Local research found no credible first-party statement of Catawiki auction internals; none is claimed. The ordinary polished demo remains unbuilt until Session 2.
Relevant files: `README.md`, `docs/case-study.md`, `docs/catawiki-alignment.md`, `docs/walkthrough.md`, `docs/interview-guide.md`, `docs/code-map.md`, `docs/learning-guide.md`, `docs/engineering-journal.md`, `docs/progress.md`, `docs/handoffs/latest.md`.
Relevant ADRs: ADR-003, 004, 005, 006, 010, 011, 012, 013, 016, 019, 020 as applicable.
Next-session starting point: Read this plan, latest handoff and Phase 23 spec. Inspect `apps/api/script/phase21_final.rb` and Compose/auth helper; design the deterministic showcase fixture and guide, run it end-to-end, then perform final audits and gates. Do not start Phase 24.

## Decisions

- Three flagship experiments: final-second contention, ambiguous committed command, and PostgreSQL PITR with ahead derived systems. Other mechanisms are supporting evidence.
- The live showcase will be a short deterministic local auction path. PITR is explained using retained evidence, not repeated in the ordinary demo.

## Claim and evidence inventory

| Claim | Source/evidence | Case-study location | Demo relevance | Confidence | Limit |
| --- | --- | --- | --- | --- | --- |
| Same-auction writes serialize and decide from post-lock state/time | [independent DB-session tests](../../apps/api/spec/integration/concurrent_bidding_spec.rb), [maximum tests](../../apps/api/spec/integration/concurrent_maximum_bidding_spec.rb), [ADR-003](../adr/003-auction-concurrency-control.md), [ADR-005](../adr/005-auction-deadlines-and-soft-close.md) | Hard problem 1 | Main | High, real PostgreSQL sessions | Hot row; no FIFO/fairness |
| Stepped/reserve/rapid policies share the locked command path | [Phase 21 combined live run](../marketplace/phase-21-final.md#combined-scenario-and-failure-behavior), [ADR-018](../adr/018-stepped-bid-increments.md), [ADR-019](../adr/019-hidden-reserve-policy.md), [ADR-020](../adr/020-auction-closing-policies.md) | Problem 1 and alignment | Main | High, local Compose/browser/tests | Public Catawiki behavior only approximated |
| A 600-contender local final-ten burst kept coherent authority | [Phase 14 run summary](../benchmarks/phase-14-session-2.md#closing-storm-and-final-ten-second-challenge), [exact report](../benchmarks/p14-20261001T140944Z-9e4ab8a6-challenge/report.md) | Problem 1 | Discussion | High for that run | 1 accepted/599 expected rejected; no simultaneous Rails execution proof or production capacity |
| Lock time did not dominate one observed HTTP tail | [Phase 15 final](../benchmarks/phase-15-final.md#causal-model) | What changed assumptions | Discussion | High for measured local window | Exact pre-Rack per-request time unavailable; shared-host drift |
| Same-key retry replays a committed historical result across replicas | [request specs](../../apps/api/spec/requests/idempotency_spec.rb), [concurrent specs](../../apps/api/spec/integration/concurrent_idempotency_spec.rb), [Phase 20 A/B run](../security/phase-20-final.md#final-verification), [ADR-006](../adr/006-client-command-idempotency.md), [ADR-017](../adr/017-versioned-keyed-idempotency-digests.md) | Hard problem 2 | Optional | High, local integration | Physical retention/keyring/client discipline |
| Auction revision and outbox intent commit together | [outbox tests](../../apps/api/spec/integration/transactional_outbox_spec.rb), [ADR-010](../adr/010-transactional-public-outbox.md) | Architecture/async | Optional | High, real PostgreSQL | Later delivery may duplicate/delay |
| Kafka duplicate does not duplicate durable audit effect | [Phase 22 Kafka replay](../operations/phase-22-kafka-recovery.md#observed-sequence-and-evidence-index), [invariants](../invariants.md#phase-10-kafka-invariants) | Async and problem 3 | Optional | High, local replay | At-least-once transport; downstream consumers need their own dedupe |
| Redis can be rebuilt from PostgreSQL | [reconciliation invariants](../invariants.md#phase-12-reconciliation-invariants), [Phase 22 replay](../operations/phase-22-kafka-recovery.md#observed-sequence-and-evidence-index) | Hard problem 3 | Optional | High, local rebuild | Ahead/conflicting state requires explicit handling |
| PITR can leave Kafka/Redis ahead of restored authority | [Phase 22 final game day](../operations/phase-22-final.md#integrated-local-game-day), [Kafka recovery report](../operations/phase-22-kafka-recovery.md) | Hard problem 3 | Report only | High, isolated local drill | Procedural fencing, nonzero RPO; no production DR proof |
| Catawiki publicly describes selected matching auction behaviors | Current first-party source register below; [Phase 21 result](../marketplace/phase-21-final.md) | [Alignment](../catawiki-alignment.md) | Policy intro | High for accessed public pages | Product experiments/change; Catawiki internals unknown |

## Public-source research

All first-party Catawiki pages accessed **2026-10-07**. The [canonical sourced comparison](../catawiki-alignment.md) contains the detailed claims and differences.

| URL | Title | Accessed | Claim supported | Source type |
| --- | --- | --- | --- | --- |
| https://www.catawiki.com/en/help/bidding-basics/how-is-the-next-minimum-bid-calculated | How is the next minimum bid calculated? | 2026-10-07 | Current 14 price bands and lot-experiment caveat | First-party Help Centre |
| https://www.catawiki.com/en/help/max-bids/what-is-a-max-bid-and-how-does-it-work | What is a max bid and how does it work? | 2026-10-07 | Private ceiling, counters, partial increment, tie, reserve and late extension | First-party Help Centre |
| https://www.catawiki.com/en/help/bidding-basics/there-are-two-identical-highest-bids-how-is-that-possible | There are two identical highest bids | 2026-10-07 | Earlier maximum priority; displayed equal amounts can reflect currency conversion | First-party Help Centre |
| https://www.catawiki.com/en/help/reserve-prices/i-d-like-to-place-a-bid-on-an-object-with-a-reserve-price-what-does-this-mean-and-how-do-i-know-what-the-reserve-price-is | I'd like to place a bid on an object with a reserve price | 2026-10-07 | Hidden reserve, below-reserve history, max below/above reserve, unsold | First-party Help Centre |
| https://www.catawiki.com/en/help/during-auction-changes-to-removal-of-lots/can-i-edit-my-reserve-price | Can I edit my reserve price? | 2026-10-07 | Seller may lower/remove active reserve with limits | First-party Help Centre |
| https://www.catawiki.com/en/help/bidding-basics/why-are-bidding-times-for-some-lots-occasionally-made-longer | Why are bidding times for some lots occasionally made longer? | 2026-10-07 | Regular final-60/+90, Live final-15/+10 | First-party Help Centre |
| https://www.catawiki.com/en/help/bidding-on-catawiki/catawiki-live-for-buyers | Catawiki Live for Buyers | 2026-10-07 | Seller stream/chat and Live extension scope | First-party Help Centre |
| https://www.catawiki.com/en/help/about | About Catawiki | 2026-10-07 | 75,000+ weekly objects, 600+ auctions, 10M+ monthly visitors, 60+ markets, 17 languages | First-party corporate/help page |
| https://www.catawiki.com/en/help/bidding-basics/what-is-a-bid-reservation | What is a bid reservation? | 2026-10-07 | Payment admission beyond Hammerfall scope | First-party Help Centre |

Research note: first-party careers/public engineering searches did not establish a current Catawiki auction-storage, lock or event architecture. No internal stack inference is included.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Starting state | `git status --short`, handoff/spec review | Clean; Phase 22 complete at requested starting commit | Handoff and commit |
| Catawiki refresh | First-party Help Centre/About page searches and reads, 2026-10-07 | Current band table, maximum/reserve/extension behavior and active reserve editing confirmed | Source table above and [alignment](../catawiki-alignment.md) |
| Evidence selection | Targeted Phase 14/15/20/21/22 reports, tests and ADRs | Three stories selected; numeric claims bounded to local experiments | Claim table above |
| Local Markdown links | Python relative-target and heading-slug audit across all changed/new docs | 304 links checked, 0 missing targets/anchors | Terminal result; repeat after Session 2 edits |
| Claim language | `rg` for inflated phrases across new prose | Matches reviewed: only negations or discussion of exactly-once as a rejected claim | Terminal result |
| Markdown structure | Fence count and manual Mermaid flowchart review | Fences balanced; Mermaid CLI unavailable | README/case-study diagrams |
| Staged whitespace | `git diff --cached --check` | Passed | Documentation-only staged diff |
| Product regression | Not run: documentation-only changes | Phase 22 product gates remain last complete evidence | [Phase 22 final](../operations/phase-22-final.md#final-local-regression-and-remaining-gate) |

## Session 2 demo concept

One Compose startup, one deterministic seed/prep step, and a guided 10-minute path through two authenticated bidders, proxy/increment/reserve, controlled late contention, authoritative result, and optional same-key replay. No ordinary-demo PITR or paid cloud dependency. Session 2 must build and execute this flow.
