# Phase 23 ExecPlan — case study and demo

Status: COMPLETE locally; closure SHA requires exact-SHA hosted CI verification before final report.
Current milestone: Closure commit and hosted CI.
Completed: First-party Catawiki comparison, three flagship stories, architecture diagram, case study, README, 60-second opening, timed walkthrough, interview guide, real-scale discussion, single-command showcase and concise demo guide.
Verified: Stopped-container Compose build/start; three repeat showcase passes plus two final checks; ordinary authenticated lifecycle smoke; 56 focused request examples; targeted RuboCop, Bash/shellcheck, privacy, 331 local links/anchors, nine public sources, reader-time and claim review.
Remaining: Commit/push closure state; inspect hosted API/web/Compose results on that exact SHA.
Known failures/limitations: Two initial showcase runs timed out because the Rails runner cached externally updated SQL counts; `ApplicationRecord.uncached` fixed this, followed by four passing runs. No product code or schema changed. Mermaid CLI unavailable; both diagrams manually syntax-reviewed. No production capacity, managed DR, cloud or Catawiki-internal claims.
Relevant files: `scripts/showcase`, `apps/api/script/showcase.rb`, `README.md`, `docs/demo.md`, `docs/case-study.md`, `docs/catawiki-alignment.md`, `docs/walkthrough.md`, `docs/interview-guide.md`, `docs/progress.md`, `docs/handoffs/latest.md`.
Relevant ADRs: ADR-003, 004, 005, 006, 010, 011, 012, 013, 016, 019, 020 as applicable.
Next-session starting point: None expected if exact-SHA hosted CI passes. Phase 24 requires a separate explicit request.

## Decisions

- Three flagship experiments: final-second contention, ambiguous committed command, and PostgreSQL PITR with ahead derived systems. Other mechanisms are supporting evidence.
- The live showcase will be a short deterministic local auction path. PITR is explained using retained evidence, not repeated in the ordinary demo.
- Each showcase run creates a labelled unique fixture through HTTP and retains it for inspection. It never deletes unrelated development rows. A 30-second initial window gives time to authenticate and display initial state; Bob bids in a bounded last-12-second window.
- The runner uses uncached SQL reads for async convergence. Redis and Kafka are observers after commit, never authorities for the bid.

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
| Session 1 product regression | Not run: Session 1 changed documentation only | Phase 22 was the last broad product gate at that milestone | [Phase 22 final](../operations/phase-22-final.md#final-local-regression-and-remaining-gate) |
| Fresh ordinary Compose startup | `docker compose down` (volumes retained), `docker compose up --build --wait` | Build/start passed in about 29 seconds; all required app/data services healthy | `/tmp/hammerfall-phase23-compose-start.log` |
| Showcase repetition | `./scripts/showcase` after fresh startup, then twice more | IDs 799/800/801, all passed at 41.9/41.7/41.9 seconds; revision 5 in PostgreSQL/Redis and five Kafka audit receipts each | `/tmp/hammerfall-phase23-showcase-{1,2,3}.log` |
| Final output/replay checks | `./scripts/showcase` after output-label edit and after uncached replay-count review | IDs 803/804 passed in 41.0/42.6 seconds; public/internal labels, replay row counts and privacy checked | `/tmp/hammerfall-phase23-showcase-{final,verified}.log` |
| Ordinary authenticated flow | `docker compose exec -T -e API_BASE_URL=http://127.0.0.1:3000 api ruby < scripts/smoke-api` | Passed; retained auction 802 | Terminal result |
| Focused API regression | `bundle exec rspec spec/requests/auctions_spec.rb spec/requests/idempotency_spec.rb` in test container | 56 examples, 0 failures (seed 38037) | Terminal result |
| Static/privacy | Targeted RuboCop; `bash -n`; shellcheck; `git diff --check`; sensitive-term scan of successful output logs | 1 Ruby file/0 offenses; shell checks passed; no sensitive terms found in output | Terminal result |
| Final Markdown links/anchors | Local path and heading-slug audit on 13 final docs | 331 checked; 0 problems | `/tmp/phase23_link_audit.py` (local, not committed) |
| Public sources and claim language | Opened nine registered first-party Catawiki URLs; targeted inflated-claim scan | All reachable and mapped; no inferred internals or unsupported positive guarantees | [Alignment](../catawiki-alignment.md) |
| Reader simulation | README opening/table/diagram, case-study architecture and three stories, selected evidence/limits | 1,937 route words / 225 technical wpm ≈ 8.6 minutes, plus ≈1–1.5 minutes for diagram/evidence; fits roughly ten minutes | Reader review below |

## Definition of Done reconciliation

| Phase 23 deliverable | Verified artifact |
| --- | --- |
| 60-second explanation | [Walkthrough opening](../walkthrough.md#000100--opening-about-60-seconds) and README introduction |
| 10–15 minute walkthrough | [Timed guide](../walkthrough.md), including exact showcase and evidence transitions |
| Three flagship experiments | [Case study](../case-study.md): contention, ambiguous committed response, PITR ahead-state |
| Primary architecture diagram | [Authoritative/derived flowchart](../case-study.md#architecture-in-one-picture) |
| Engineering case study | [Problem/decision/alternative/experiment/limit sections](../case-study.md) |
| Catawiki alignment | [Dated first-party comparison](../catawiki-alignment.md), with unknown internals explicit |
| Real-scale discussion | [Measured triggers and candidate changes](../interview-guide.md#what-would-change-at-real-scale) |
| Conversation prompts | [Questions for Catawiki engineers](../interview-guide.md#questions-for-catawiki-engineers) |
| Simple reproducible demo | [Single command and guide](../demo.md), fresh startup and repeat runs above |

## Final reader and adversarial review

The top of README answers what Hammerfall is, why bids are hard, what was
actually exercised and the limits in 289 words plus a small table; that is
about 75 seconds at 230 words/minute before a brief table scan. The engineer
route includes the primary diagram, three hard-problem sections, evidence and
limits. At approximately 1,937 words plus diagram/evidence allowance it is
roughly 9.5–10 minutes. The interview guide gives direct deeper links for row
locking, proxy bidding, deadlines, idempotency, outbox, Kafka, Redis, PITR,
performance and security. This is a structured reading estimate, not a timed
external reader study.

Final review: the showcase does not inject simultaneous bids, lost transport or
PITR; those use separate retained tests/reports. The HTTP bid path and database
row counts agree, the replay leaves bid/outbox/revision unchanged, the closer
finalizes the expected winner, and Kafka/Redis are checked only after authority.
Unique retained fixtures avoid deleting unrelated data. Bounded waits fail
clearly. Successful output omits passwords, cookies, CSRF, private values from
server state, raw command keys and secrets. No code path changes auction
behavior. Mermaid CLI was absent; the README and case-study flowcharts were
manually checked for balanced fences and valid node/edge syntax.
