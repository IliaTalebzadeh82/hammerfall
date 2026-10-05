# Phase 22 ExecPlan — Durability, Release & Operations

Status: Operations implementation/focused-test milestone verified; Phase 22 remains in progress.
Current milestone: checkpoint before the integrated live game day and final regression.

## Decisions

| Topic | State | Decision / evidence |
| --- | --- | --- |
| State classification | ADOPT | PostgreSQL owns auction, bid, command, outbox, user/session and audit/receipt rows; Redis projection/rate limits and Sidekiq queue are derived/operational. [Inventory](../operations/phase-22-session-1.md). |
| Backup scope / PITR mechanism | ADOPT | Physical PostgreSQL 18 base backup plus continuous archived WAL, verified by restore. Logical dump is supplementary, not PITR. |
| Backup verification | ADOPT | `pg_verifybackup` plus isolated domain-correct restore; success of backup command alone is insufficient. |
| Restore ordering | ADOPT | Fence writers/async roles, restore and validate PG and secrets, quarantine future Kafka, replace/seed Redis, requeue retained intents under review, reconcile, resume traffic last. [Runbook](../runbooks/database-recovery.md). |
| RPO semantics / RTO measurement | ADOPT | T3 client success can be lost when target is after T2. Report only local step timings; no production objective or RTO claim. |
| Secret recovery | ADOPT | Keep every HMAC version needed by any retained row in any restorable backup; restore shared `SECRET_KEY_BASE`, credentials and trust roots separately. |
| Redis recovery | ADOPT | Valid ahead key blocks lower seed; clear projection namespace after PITR and rebuild from restored PG. Verified locally. |
| Kafka recovery | ADOPT, LOCAL | Dedicated old broker contained and consumed discarded revision 5. It was stopped; a fresh broker received only restored outbox revisions 1–4. Audit, Redis and reconciliation converged. [Checkpoint](../operations/phase-22-kafka-recovery.md). Managed Kafka DR remains unverified. |
| Outbox after restore | ADOPT | Three restored Kafka acknowledgments were deliberately requeued. Old receipts returned duplicate for 1–3; missing revision 4 produced one durable effect. Redis revision guard absorbed stale/duplicate replay. Sidekiq replay remains to be exercised. |
| Idempotency after restore | ADOPT | T2 historical command replayed; T3 absent. Retained key material is required. |
| Migration / old-new app / worker compatibility | ADOPT | Old app writes fixed data on expanded schema but misprices stepped row. V2 readers first; policy/HMAC writer drain required. [Matrix](../operations/release-compatibility.md). |
| Schema/application rollback | ADOPT | Keep expanded schema and revert image only before incompatible data/events; after policy data, forward fix. Rapid downgrade guard verified. |
| Artifact promotion / failed rollout | ADOPT | Record Git SHA, immutable image digests, schema/event/config versions; same digest promotion is policy, pipeline not implemented. Failed readiness path follows matrix. |
| Integrated game day / closure | REMAINING | Live Sidekiq, fence, alert, operator, resume and normal-user proof; then final regression, docs and exact-SHA hosted CI. |
| Sidekiq authority and recovery | ADOPT, CODE REVIEW | Three job classes only: outbox-backed notification hint, PostgreSQL read-only sweep, and PostgreSQL/Redis projection scan. No auction truth exists only in Sidekiq. Regenerate retained hints from outbox and scans from scheduler/leases; do not bulk retry old Redis. [Policy](../operations/phase-22-final.md). Live queue/Retry/Dead proof pending. |
| Recovery traffic fence | ADOPT, FOCUSED TEST | All versioned API reads/writes return controlled 503 with `RECOVERY_FENCE=true`; both Compose replicas receive setting. Ingress isolation and stopped writers are still mandatory. Read traffic is fenced during PITR because PG and Redis may be unavailable/ahead. Live request during game day pending. |
| Indicators and alerts | ADOPT, STATIC CHECK | Four Prometheus rules use actual outbox age, operator-review, mutation 5xx and close-lag series. Thresholds provisional; production SLO/RPO/RTO unset. Kafka lag gauge is stale when idle, so diagnostic only. `promtool check config` passes. Live alert transition pending. |
| Operator boundary | ADOPT, FOCUSED TEST | Disabled-by-default internal API, Phase 20 operator role/session/CSRF, bounded diagnosis and one-auction derived projection reconciliation. PostgreSQL audit rows record actor/target/action/result/time; no authority mutation. Seven focused request examples pass. Live operator workflow pending. |
| Production RPO/RTO and Cloud SQL restore | NEEDS EVIDENCE | No deployed infrastructure, representative data size or secret-store recovery exercise. |

## Progress

Completed: isolated recovery Compose/harness and Phase 21 fixture; physical T2 PITR, retained replay, ahead Redis rebuild; real Phase 20 worktree compatibility and rollback guard drill; inventory, compatibility policy, recovery/release runbooks and Session 1 report.

Verified: final sanitized/credentialed run at LSN `0/400C3D0`; `pg_verifybackup` passed; T1/T2 survived, T3 excluded; private maximum verified without logging; Redis 5→4 required key deletion. Old app accepted 36,000 in a rolled-back transaction; new app required 37,000. Old app fixed write/new app read passed; rollback guard preserved schema. Focused backend 73 examples/0 failures/1 opt-in pending. RuboCop fixture, shellcheck and bash syntax passed.

Session 2 Kafka milestone: `PHASE22_KAFKA_DRILL=1 scripts/recovery/phase22-pitr` passed using isolated old/fresh Kafka brokers and PostgreSQL/Redis. Old Kafka and Redis reached revision 5; PITR restored PostgreSQL to 4. Old broker stayed stopped. Fresh broker received only retained events 1–4. Restored audit receipts returned three duplicates and one new effect; projection replay returned three stale and one duplicate. Redis matched the PostgreSQL presenter and reconciliation was healthy. The first attempt exposed `db:prepare` seeding unrelated demo auctions; the harness now migrates without seeds and the full drill passed. [Checkpoint report](../operations/phase-22-kafka-recovery.md).

Operations implementation milestone: classified all three Sidekiq jobs by authority; added a request-level 503 recovery guard for both API replicas, disabled-by-default role-gated operator diagnostic/one-auction projection repair with durable action audit, four Prometheus alerts, and provisional SLI/severity/ownership/runbook policy. Seven focused request examples passed; migration rollback/reapply, targeted RuboCop, Zeitwerk, Prometheus config/rules, Compose config and diff whitespace checks passed. Initial focused test failed because a Redis projection key from another test remained for a reused auction ID; key setup/cleanup fixed it. Editing the already applied test migration caused a local redo failure; the isolated test table/version were reset and fresh migration plus subsequent rollback/reapply passed. No domain failure was suppressed.

Remaining: live Sidekiq queue/Retry/Dead classification, actual ingress/API fence attempt and safe resume, integrated isolated PITR game day with live alert healthy→firing→cleared, operator path, release mini-drill, adversarial review, full backend/frontend/static/Compose/browser gates, affected final documentation, closure commit and exact-SHA hosted CI. Do not start Phase 23.

Known limitations: Cloud SQL PITR, managed Kafka DR, secret-store retrieval, live Sidekiq recovery, end-to-end traffic freeze/resume, representative data volumes and production RPO/RTO are unverified. Current consumer will accept future Kafka revisions after PG PITR if old broker is resumed; the tested procedure depends on strict old-broker quarantine and distinct endpoint configuration. No application-level timeline guard was added. `RECOVERY_FENCE` is a per-process defense, not a distributed lock; every ingress and writer replica must still be controlled. Existing Kafka lag metrics may be stale when consumers stop; the alert set deliberately omits a lag rule. Prometheus rules have syntax proof but no live firing/clearing proof yet.

Relevant files: `scripts/recovery/`, `apps/api/script/phase22_recovery_fixture.rb`, `apps/api/app/controllers/api/v1/operator_auctions_controller.rb`, `apps/api/app/controllers/api/v1/base_controller.rb`, `infrastructure/observability/hammerfall-alerts.yml`, `docs/operations/phase-22-final.md`, `docs/operations/phase-22-session-1.md`, `docs/operations/release-compatibility.md`, `docs/runbooks/database-recovery.md`, `docs/runbooks/release.md`.

Relevant ADRs: 003, 006, 010–013, 017–020.

Next-session starting point: Read `AGENTS.md`, handoff, Phase 22 spec and this plan. Reuse the verified `PHASE22_KAFKA_DRILL=1 scripts/recovery/phase22-pitr` infrastructure. Extend/run one integrated isolated game day to inspect Sidekiq queue/Retry/Dead before Redis replacement, prove an actual fenced API mutation gets 503 without a write, observe `OutboxBacklogOld` in live Prometheus from healthy to firing to cleared, restore and converge PG/Kafka/Redis/Sidekiq, verify T2 replay/T3 absence and operator diagnostics. Record coarse times and authority snapshots. Then run release mini-drill, adversarial review, broad final gates and closure docs. Do not infer live proof from these focused tests or syntax checks.

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Starting state | `git status --short`, `git log -1` | Clean; `7b776094...` | Session 1 startup |
| Physical base and WAL PITR | `scripts/recovery/phase22-pitr` | PG 18.6; `pg_verifybackup` passed; target `0/400C3D0`; T2 yes/T3 no | `apps/api/tmp/phase22-pitr-final-secure.log` (ignored); [report](../operations/phase-22-session-1.md) |
| Retained replay/outbox/private state | Fixture `verify` against promoted DB | Replay 201 without new bid/outbox; rev 4; private max asserted | Same local log; private value omitted |
| Ahead Redis and rebuild | Fixture `seed`, `delete_projection`, `seed` | Rev 5 seed stale; targeted delete; rev 4 applied | Same local log |
| Old/new app and rollback | `PHASE22_WORK_DIR=... scripts/recovery/phase22-compatibility` | Old fixed write/new read; old stepped 36,000 accepted then rolled back; new rejected; migration down guarded; missing-keyring release preflight failed as expected | `apps/api/tmp/phase22-compatibility-secure.log`, `phase22-failed-release.log` (ignored) |
| Focused backend regression | RSpec idempotency, outbox, Redis projection, Kafka outbox | 73 examples, 0 failures, 1 opt-in live Kafka pending; seed 58967 | `apps/api/tmp/phase22-focused-rspec.log` (ignored) |
| Tooling lint | `bundle exec rubocop script/phase22_recovery_fixture.rb`; `shellcheck`; `bash -n` | 1 Ruby file no offenses; shell checks pass | Session 1 checks |
| Kafka-ahead threat and isolation | `PHASE22_KAFKA_DRILL=1 scripts/recovery/phase22-pitr` | Old broker projected revision 5; stopped before PITR; restored PostgreSQL revision 4; fresh broker only 1–4 | `apps/api/tmp/phase22-kafka-drill.log` (ignored); [checkpoint](../operations/phase-22-kafka-recovery.md) |
| Kafka/outbox replay and dedupe | Same drill, actual publisher and both consumers | Four requeued rows; audit results duplicate×3/next×1; Redis stale×3/duplicate×1; receipts/audit count 4 | Same log |
| Redis and reconciliation | Same drill | Ahead 5 rejected lower seed; delete + seed 4; exact public fields; `AuctionProjectionReconciler#check = healthy` | Same log |
| Session 2 focused lint | `bundle exec rubocop script/phase22_recovery_fixture.rb`; `shellcheck scripts/recovery/phase22-pitr`; `bash -n` | No offenses/findings | This session |
| Operator/fence focused requests | `bundle exec rspec spec/requests/operator_auctions_spec.rb spec/requests/recovery_fence_spec.rb` | 7 examples, 0 failures; seed 58571 | `apps/api/tmp/phase22-ops-focused.log` (ignored) |
| Operator action audit migration | `RAILS_ENV=test bundle exec rails db:migrate:redo STEP=1` | Rollback and reapply passed, including FKs/check constraints | Console result, schema.rb |
| Ops Ruby/static checks | Targeted `bundle exec rubocop`; `bundle exec rails zeitwerk:check` | 7 Ruby files no offenses; eager load passed | This checkpoint |
| Alert/Compose syntax | `promtool check config`; `docker compose config --quiet`; `git diff --check` | Prometheus config valid, four rules found; Compose and whitespace pass | This checkpoint |

The first local PITR attempt failed on shell quoting in `postgresql.auto.conf` generation before recovery startup; the error was fixed and the complete exercise rerun successfully. The first focused RSpec attempt lacked the local PostgreSQL password; sourcing `.env` and rerunning produced the result above. Neither failure was a domain test failure.
