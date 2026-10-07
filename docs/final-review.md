# Phase 24 final engineering review

Review date: 2026-10-07. Scope: the Phase 24 repository audit, repairs and
retained evidence. The [ExecPlan](plans/phase-24-execplan.md) is the finding
register and exact local evidence index. This review evaluates what the code and
tests establish; it does not certify a production auction service.

## Review method and result

The review compared the public [case study](case-study.md), [architecture](architecture.md),
[invariants](invariants.md), [production limits](production-readiness.md),
current API/frontend contracts and seven runbooks with their implementation and
targeted tests. It inspected authority and lock order, retry ownership,
asynchronous acknowledgment, projection repair, access control, public/private
representations, recovery timeline handling, CI gates, dependency advisories,
local infrastructure manifests and evidence claims. The final local regression,
Compose integration, browser suite and showcase were run after the Phase 24 code
changes. Historical PITR and load campaigns were reviewed from retained reports
and not rerun because their machinery did not change.

The register contains 28 findings: zero Critical; one High fixed; eleven Medium
(ten fixed, one deferred external metadata action); ten Low (eight fixed, two
accepted); six Informational (five verified without a defect, one accepted).
There is no known unresolved Critical or High finding and no confirmed auction
authority defect from this review. The one open Medium item is the public GitHub
description, which still says “Production-grade”; the proposed replacement is
in P24-008 and requires repository-settings access unavailable during this
phase. A missing license is an explicit owner decision, not an inferred grant.

## Adversarial checks

| Challenge | What was checked and observed | Residual boundary |
| --- | --- | --- |
| Can concurrent bids or the closer decide from stale state? | `Auction` reloads under the PostgreSQL row lock, then samples `AuctionClock`; bid, proxy, deadline, history, public revision and outbox intent settle in one transaction. Independent-session concurrency, close races, cross-replica HTTP and the Phase 21 combined scenario passed. | Lock acquisition is not FIFO. A hot row and waiting connections limit throughput; no exact closer SLA or production capacity is proved. |
| Can a lost response become a duplicate command? | `Idempotency::Executor` takes a scoped advisory lock before key lookup/claim and the auction lock. The terminal public result commits with the command. Same actor/key/payload replay returns historical output; browser and integration evidence then fetch current state. Unexpected database failures are not recorded as success. | Clients must preserve the key/payload. Physical pruning ends the retained-key guarantee, and PITR can discard an acknowledged later command. HMAC keyring/drain compatibility is operationally required. |
| Can an event, cache or socket decide auction truth? | Outbox publishers acknowledge independently; Kafka audit receipts and Redis revision/digest guards tolerate duplicate/stale delivery. Reconciliation uses PostgreSQL as desired state and escalates ahead/conflicting/corrupt projections. Cable sends a revision hint and the browser uses REST. Live Kafka/Redis/Compose and browser checks passed. | Delivery remains at least once. Poison rows need operator action; Redis or an open browser may remain stale. Publishers hold a database row lock/connection through external I/O (P24-014 accepted). |
| Can recovery silently accept a discarded future? | The retained isolated PITR and game-day evidence restored PostgreSQL between T2/T3, fenced traffic, quarantined old Kafka, rebuilt Redis/Sidekiq and republished retained outbox state. The restored T2 replay survived; discarded T3 did not. | All-writer fencing and old-broker quarantine are procedural. T3 demonstrates nonzero RPO. There is no live managed-service restore, representative recovery volume or production RPO/RTO. |
| Can private or privileged state leak through public paths? | Public presenter/snapshot allowlists, authenticated actor derivation, CSRF, owner/operator policy, default-off operator API, request bounds, shared rate limits and tracked-secret checks were inspected against request/browser evidence. Public output omits private maxima, priority and raw command keys. | Database operators can inspect plaintext maxima. Redis-outage fallback quotas are per process; established Cable sockets can receive public hints after revocation until disconnect. No professional penetration test or public ingress proof exists. |
| Can presentation or infrastructure claims outrun evidence? | The README/case study use local test, benchmark and recovery links; current first-party Catawiki behavior is separated from unknown internals. Dashboard queries and Prometheus rules parse; ordinary Compose boots; base/GCP Kubernetes render and Terraform format pass. | Local k6 and kind do not prove production scale. GCP is an undeployed reference; Terraform provider initialization was blocked by registry access. Eight dashboard expressions had no current sample, which cannot establish operational health. |

## Verification and failure resolution

- The final `./scripts/check` passed 561 RSpec examples, zero failures, four
  optional pending (seed 22690); RuboCop checked 180 files without offenses,
  Brakeman had zero warnings, bundler-audit found no vulnerability, and
  Zeitwerk passed. Frontend tests passed 78 cases across ten files, followed by
  typecheck, lint, format, production build and `npm audit` with zero findings.
- ShellCheck and Bash syntax passed on eight tracked scripts. Compose and
  Prometheus configuration/rules passed. Base and GCP Kubernetes renders and
  the 29-resource GCP validator passed; Terraform `fmt -check` passed. Provider
  initialization could not reach the registry, and no cloud plan/apply ran.
- The rebuilt ordinary Compose stack became healthy with the corrected web
  startup grace. CI-equivalent Kafka, lifecycle, proxy, concurrency,
  cross-replica, authentication/replay and pruning integration passed. Two
  consecutive showcases reached €100 opening, €650 final price, a +10-second
  rapid extension, historical replay without mutation and PostgreSQL/Kafka/Redis
  revision agreement. The authenticated Playwright suite passed nine tests;
  one existing worker-outage chaos test remained an intentional opt-in skip.
- The initial local concurrency failures were database-pool checkout timeouts
  from a three-connection local test pool against ten sessions; matching CI's
  15-connection pool resolved them without weakening assertions. The first
  frontend build after removing vulnerable unused `shadcn` CLI found a stale
  CSS import; deleting it and updating compatible `sharp`/`source-map-js`
  packages made the full build/audit pass. Compose startup grace and showcase
  fixture time budget were corrected after live failures. No auction rule or
  schema was changed to make these gates green.

The code-bearing Phase 24 checkpoint `b3bef9a1cb3cca598f645d1b5e11a1efcfe34259`
also passed hosted `api`, `web` and `compose` in
[run 37638903729](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37638903729).
The final documentation closure commit still needs its own exact-SHA run.

The [Phase 24 ExecPlan](plans/phase-24-execplan.md#evidence-index) records command
names, counts, seeds, local log paths and the remaining exact-SHA hosted CI
gate. The [Phase 22 operations report](operations/phase-22-final.md) and
[Phase 14/15 benchmark reviews](benchmarks/README.md) retain earlier destructive
and load evidence with their limits.

## Disposition

Phase 24 fixed the reasonable High/Medium repository findings, reconciled
current-facing docs and removed unused dependency/CSS. P24-008 remains a
repository-metadata action when settings access is available. P24-009 (license),
P24-010 (ignored sensitive local recovery proof) and P24-014 (publisher lock
scope) remain accepted with the reasons in the register. No new roadmap phase
is implied. Completion additionally requires hosted `api`, `web` and `compose`
success on the exact completion commit; the final closure response records
that run.

The established ADRs still match implementation, so no architecture decision
was rewritten. Existing benchmark reports and diagrams were checked against
their stated claims; no new load result or rendered-diagram certification is
claimed. Dashboard queries were valid and its empty current series were
classified as absent telemetry, so changing dashboard expressions would not
have addressed a demonstrated defect.
