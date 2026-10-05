# Phase 22 ExecPlan — Durability, Release & Operations

Status: Session 1 milestone verified; Phase 22 remains in progress.
Current milestone: physical PITR and release compatibility documented. Session 2 owns operational policy and integrated game day.

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
| Kafka recovery | NEEDS EVIDENCE | Source shows old broker can replay discarded future event. Fresh isolated broker/requeue retained outbox is documented design; integrated exercise remains Session 2. |
| Outbox after restore | ADOPT | Restored acknowledgments may be pending again; duplicate Sidekiq/Kafka delivery is expected, not exactly once. Live T2 outbox pending state verified; external redelivery not exercised. |
| Idempotency after restore | ADOPT | T2 historical command replayed; T3 absent. Retained key material is required. |
| Migration / old-new app / worker compatibility | ADOPT | Old app writes fixed data on expanded schema but misprices stepped row. V2 readers first; policy/HMAC writer drain required. [Matrix](../operations/release-compatibility.md). |
| Schema/application rollback | ADOPT | Keep expanded schema and revert image only before incompatible data/events; after policy data, forward fix. Rapid downgrade guard verified. |
| Artifact promotion / failed rollout | ADOPT | Record Git SHA, immutable image digests, schema/event/config versions; same digest promotion is policy, pipeline not implemented. Failed readiness path follows matrix. |
| Operator requirements / game day | DEFER | Session 2 owns SLOs, alerts, secured workflow and integrated recovery/deploy game day. |
| Production RPO/RTO and Cloud SQL restore | NEEDS EVIDENCE | No deployed infrastructure, representative data size or secret-store recovery exercise. |

## Progress

Completed: isolated recovery Compose/harness and Phase 21 fixture; physical T2 PITR, retained replay, ahead Redis rebuild; real Phase 20 worktree compatibility and rollback guard drill; inventory, compatibility policy, recovery/release runbooks and Session 1 report.

Verified: final sanitized/credentialed run at LSN `0/400C3D0`; `pg_verifybackup` passed; T1/T2 survived, T3 excluded; private maximum verified without logging; Redis 5→4 required key deletion. Old app accepted 36,000 in a rolled-back transaction; new app required 37,000. Old app fixed write/new app read passed; rollback guard preserved schema. Focused backend 73 examples/0 failures/1 opt-in pending. RuboCop fixture, shellcheck and bash syntax passed.

Remaining: Session 2 SLI/SLO and alert policy, ownership/secured operator workflow, integrated Kafka/outbox/Redis recovery game day, final broader regression/Compose/browser/CI as warranted, final Phase 22 closure docs. Do not start Phase 23.

Known limitations: Kafka reset/republication, Cloud SQL PITR, secret-store retrieval, end-to-end traffic freeze/resume, representative data volumes and production RPO/RTO are unverified. Current consumer will accept future Kafka revisions after PG PITR if old broker is resumed; runbook explicitly fences it.

Relevant files: `scripts/recovery/`, `apps/api/script/phase22_recovery_fixture.rb`, `docs/operations/phase-22-session-1.md`, `docs/operations/release-compatibility.md`, `docs/runbooks/database-recovery.md`, `docs/runbooks/release.md`.

Relevant ADRs: 003, 006, 010–013, 017–020.

Next-session starting point: Read `AGENTS.md`, handoff, Phase 22 spec and this plan. Inspect the runbooks/report. Plan Session 2 integrated test of the fresh-Kafka/requeued-outbox path before claiming that recovery procedure works; then complete operational policy/game day and final verification.

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

The first local PITR attempt failed on shell quoting in `postgresql.auto.conf` generation before recovery startup; the error was fixed and the complete exercise rerun successfully. The first focused RSpec attempt lacked the local PostgreSQL password; sourcing `.env` and rerunning produced the result above. Neither failure was a domain test failure.
