# Phase 22 ExecPlan — Durability, Release & Operations

Status: Integrated local game day verified; Phase 22 remains in progress.
Current milestone: Context checkpoint after the game day. Next session owns adversarial review, final regression, closure commit and exact-SHA hosted CI. Started from `becc971f0d9d76cf8dc20a64a2c8e384156df842`.

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
| Integrated game day / closure | LIVE VERIFIED / REMAINING | Clean isolated run proved Sidekiq, fence, alert inactive→pending→firing→cleared, operator, PITR convergence and resumed authenticated bid. Final regression, adversarial review, docs and exact-SHA hosted CI remain. |
| Sidekiq authority and recovery | ADOPT, LIVE VERIFIED | Three observed job classes: five hints and one of each scan; Retry/Dead/Scheduled zero. Old Redis queue discarded; four retained hints and both scans regenerated and drained, without authority mutation. [Policy](../operations/phase-22-final.md). |
| Recovery traffic fence | ADOPT, LIVE VERIFIED | Authenticated mutation through isolated ingress and both direct replicas returned controlled 503 with headers; versioned read 503; bid/command/outbox/revision unchanged. Ingress isolation and stopped writers remain mandatory. |
| Indicators and alerts | ADOPT, LIVE VERIFIED | Four unchanged Prometheus rules; clean isolated metric 0/rule inactive→pending→firing at 216 s→metric 0/rule inactive. Local Collector expiration set to 1m for repeatable recovery; ordinary Collector remains 5m default. Thresholds provisional; production SLO/RPO/RTO unset. |
| Operator boundary | ADOPT, LIVE VERIFIED | Separate loopback operator process; anonymous 401/member 403/operator 200. Bounded diagnosis, one-auction missing-projection repair, PostgreSQL audit actor/target/action/result/time and security event; authority unchanged. Ordinary API defaults disabled. |
| Production RPO/RTO and Cloud SQL restore | NEEDS EVIDENCE | No deployed infrastructure, representative data size or secret-store recovery exercise. |

## Progress

Completed: isolated recovery Compose/harness and Phase 21 fixture; physical T2 PITR, retained replay, ahead Redis rebuild; real Phase 20 worktree compatibility and rollback guard drill; inventory, compatibility policy, recovery/release runbooks and Session 1 report.

Verified: final sanitized/credentialed run at LSN `0/400C3D0`; `pg_verifybackup` passed; T1/T2 survived, T3 excluded; private maximum verified without logging; Redis 5→4 required key deletion. Old app accepted 36,000 in a rolled-back transaction; new app required 37,000. Old app fixed write/new app read passed; rollback guard preserved schema. Focused backend 73 examples/0 failures/1 opt-in pending. RuboCop fixture, shellcheck and bash syntax passed.

Session 2 Kafka milestone: `PHASE22_KAFKA_DRILL=1 scripts/recovery/phase22-pitr` passed using isolated old/fresh Kafka brokers and PostgreSQL/Redis. Old Kafka and Redis reached revision 5; PITR restored PostgreSQL to 4. Old broker stayed stopped. Fresh broker received only retained events 1–4. Restored audit receipts returned three duplicates and one new effect; projection replay returned three stale and one duplicate. Redis matched the PostgreSQL presenter and reconciliation was healthy. The first attempt exposed `db:prepare` seeding unrelated demo auctions; the harness now migrates without seeds and the full drill passed. [Checkpoint report](../operations/phase-22-kafka-recovery.md).

Operations implementation milestone: classified all three Sidekiq jobs by authority; added a request-level 503 recovery guard for both API replicas, disabled-by-default role-gated operator diagnostic/one-auction projection repair with durable action audit, four Prometheus alerts, and provisional SLI/severity/ownership/runbook policy. Seven focused request examples passed; migration rollback/reapply, targeted RuboCop, Zeitwerk, Prometheus config/rules, Compose config and diff whitespace checks passed. Initial focused test failed because a Redis projection key from another test remained for a reused auction ID; key setup/cleanup fixed it. Editing the already applied test migration caused a local redo failure; the isolated test table/version were reset and fresh migration plus subsequent rollback/reapply passed. No domain failure was suppressed.

Game-day milestone: `PHASE22_KAFKA_DRILL=1 PHASE22_LIVE_DRILL=1 scripts/recovery/phase22-pitr` passed with dedicated telemetry. `pg_verifybackup`; T1/T2 retained and T3 absent; old Kafka/Redis rev 5 replaced by fresh rev 1–4 and Redis rev 4; audit duplicate ×3/next ×1; Sidekiq jobs classified/regenerated/drained; real ingress and both replicas fenced without authority mutation; alert metric 0/inactive→216/firing→0/inactive; operator HTTP authorization/diagnosis/repair/audit and resumed authenticated 201 passed. [Timeline](../operations/phase-22-final.md). The first live attempts exposed fixture count, nginx upstream, WAL-segment-boundary and shared-telemetry-baseline errors; all were repaired and the complete clean run passed. No auction product behavior was altered.

Remaining: final adversarial and privacy review; full backend, frontend, static/security and migration gates; ordinary Compose/browser regression; final docs; closure commit/push and exact-SHA hosted CI. Do not start Phase 23.

Known limitations: Cloud SQL PITR, managed Kafka DR, secret-store retrieval, representative data volumes and production RPO/RTO remain unverified. Current consumer accepts future Kafka revisions after PG PITR if the old broker is resumed; the tested procedure depends on strict quarantine and distinct endpoint configuration. No application-level timeline guard was added. `RECOVERY_FENCE` is a per-process defense, not a distributed lock; every ingress and writer replica still needs control. Existing Kafka lag metrics may be stale when consumers stop; the alert set omits a lag rule. A stopped publisher's last gauge can persist in the Collector until metric expiration; verify process health and current series identity when interpreting alerts. The disposable game-day Collector used a one-minute expiration; ordinary configuration was unchanged. A non-blocking OTLP trace-export 404 from the ordinary Collector appeared in a fixture runner; isolated metric/alert evidence was unaffected. Review observability health during final gates.

Relevant files: `scripts/recovery/`, `apps/api/script/phase22_recovery_fixture.rb`, `apps/api/app/controllers/api/v1/operator_auctions_controller.rb`, `apps/api/app/controllers/api/v1/base_controller.rb`, `infrastructure/observability/hammerfall-alerts.yml`, `docs/operations/phase-22-final.md`, `docs/operations/phase-22-session-1.md`, `docs/operations/release-compatibility.md`, `docs/runbooks/database-recovery.md`, `docs/runbooks/release.md`.

Relevant ADRs: 003, 006, 010–013, 017–020.

Next-session starting point: Read `AGENTS.md`, handoff, Phase 22 spec and this plan; use the final game-day report rather than rerunning its successful destructive drill. Perform adversarial review, including privacy and current alert/role semantics; fix actual defects and rerun affected evidence. Run full backend/frontend/static/security/migration gates, ordinary Compose and authenticated browser suite. Reconcile final docs and Definition of Done, commit/push, inspect hosted CI on the exact closure SHA, then mark Phase 22 complete. Do not start Phase 23.

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
| Live Sidekiq state | Queue/Retry/Dead/Scheduled inspection, reset, regeneration, drain | 5 hints + 2 scans; 0 retry/dead/scheduled; regenerated 4 hints + 2 scans; queues drained | `apps/api/tmp/phase22-live-drill-clean.log`; [report](../operations/phase-22-final.md) |
| Live API fence | Authenticated mutation via ingress and direct A/B; read; DB counts/revision | 503 + Retry-After/no-store; no authority writes | Same log; [report](../operations/phase-22-final.md) |
| Live alert transition | Isolated Prometheus/Collector with unchanged rules and real Kafka backlog | Age 0/inactive→pending→216/firing→0/inactive; 15s cycle | Same log; Prometheus API observation; [report](../operations/phase-22-final.md) |
| Live operator workflow | HTTP anonymous/member/operator, diagnostics, reconcile and audit | 401/403/200; missing projection repaired; authority unchanged; privileged event emitted; public ingress operator route 404 after resume | Same log, bounded HTTP response and read-only post-run probe; [report](../operations/phase-22-final.md) |
| Integrated game day | `PHASE22_KAFKA_DRILL=1 PHASE22_LIVE_DRILL=1 scripts/recovery/phase22-pitr` | PASS: T1/T2 retained/T3 absent; future Kafka quarantined; Redis and Sidekiq rebuilt; alert cleared; fresh user bid 201 | Same log; sensitive backup directory `apps/api/tmp/phase22-recovery.ML1Hbt` (ignored) |
| Release mini-drill | Pre/post incompatible-data rollback decision using Session 1 proof | Pre-policy compatible image may roll back; post-policy old writer unsafe, keep schema/fence and forward-fix | [Report](../operations/phase-22-final.md); [compatibility](../operations/release-compatibility.md) |
| Adversarial review | Correctness, recovery, privacy, alert and release threats | Pending | Final review |
| Full backend regression | Stable isolated PostgreSQL/Redis RSpec run | Pending | Final gates |
| Frontend gates | Test/typecheck/lint/format/build | Pending | Final gates |
| Static and security | Ruby, shell, Prometheus, Compose and whitespace checks | Pending | Final gates |
| Ordinary Compose | Normal auth/auction/async multi-replica integration | Pending | Final gates |
| Browser | Authenticated real-browser suite | Pending | Final gates |
| Hosted CI | Exact closure SHA; api/web/compose jobs | Pending | Closure |
| Game-day harness lint/config | `shellcheck`, `bash -n`, focused RuboCop, recovery Compose config, `promtool check config/rules`, `git diff --check` | Passed; 4 alert rules found | This session and clean drill containers |

The first local PITR attempt failed on shell quoting in `postgresql.auto.conf` generation before recovery startup; the error was fixed and the complete exercise rerun successfully. The first focused RSpec attempt lacked the local PostgreSQL password; sourcing `.env` and rerunning produced the result above. Neither failure was a domain test failure.
