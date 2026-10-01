# Phase 15 final verification

2026-10-02 local closure gates on the rebuilt Compose stack. These are correctness and setup checks, not benchmark measurements. The [final performance review](../phase-15-final.md) uses the retained Session 1/2 runs.

| Gate | Result | Evidence |
|---|---|---|
| Focused observability, bid, maximum, idempotency, concurrency, closing and outbox specs | 138 examples, 0 failures, 1 expected pending | [focused.log](focused.log.gz) |
| Instrumentation repair | Initial full gate found `Observability::DbPoolDiagnostics` missing during Zeitwerk eager load. Repaired the module namespace and initializer; 15 observability examples passed and Zeitwerk passed. | [diagnostics-fix.log](diagnostics-fix.log.gz) |
| Full backend in API container, test Redis DB 15 | 441 examples, 0 failures, 3 expected pending; RuboCop 124 files/no offenses, Brakeman 0 warnings, bundler-audit no vulnerabilities, Zeitwerk passed | [backend.log](backend.log.gz) |
| Repository `scripts/check` on host, test Redis DB 15 | 441 backend examples, 0 failures, 4 expected pending; Ruby static/security plus frontend gates passed | [check.log](check.log.gz) |
| Frontend independent gate | Lint 48 files, format 47 files, typecheck, 73/73 Vitest tests, Next production build passed | [web-build.log](web-build.log.gz) plus `check.log.gz` |
| Rebuilt Compose | `docker compose config --quiet` and `docker compose up --build -d --wait --wait-timeout 360` passed; API, web, PostgreSQL, Redis, Kafka and required roles healthy | [compose-up.log](compose-up.log.gz) |
| Established runtime smokes | API `/up` and web HTTP passed; Redis PONG; Kafka topic 3 partitions; reconciliation scheduler, Sidekiq/outbox and Kafka publishers, Kafka end-to-end, sequential API/close, independent closer, concurrent HTTP bids, proxy bids and idempotency pruning passed | Terminal outcomes recorded below |
| Real Chrome against Compose | 7/7 Playwright scenarios passed: manual/maximum bids, response-loss retry, lifecycle, cross-client REST/Cable recovery, soft close and final winner | [browser.log](browser.log.gz) |
| Diagnostics disabled | API had `PERFORMANCE_DIAGNOSTICS=false`, `PERFORMANCE_CPU_PROFILE=false`, no control socket | Terminal check before and after opt-in smoke |
| Diagnostics enabled | Private directory mode 0700, socket 0600; five Puma samples with backlog/thread counters; explicit one-second StackProf trigger wrote nonempty dump/GC files, then both artifacts were deleted | [diagnostics-sample.jsonl](diagnostics-sample.jsonl), [diagnostics-compose.log](diagnostics-compose.log.gz) |
| Final local settings | Ignored `.env` explicitly pins OTel on after plain Compose recreate revealed its documented default is off; API healthy with OTel true, three threads/pool three, development reloading on, diagnostics/CPU profile off, no diagnostic socket. FD soft/hard 1,024/524,288. | [otel-restore.log](otel-restore.log.gz), terminal inspection |
| Hosted CI for verification commit `4949301bd10d3e8450da3641393d9b892881da58` | API, web and Compose jobs all succeeded | [GitHub Actions run 36941725862](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/36941725862) |

The first host `scripts/check` attempt stopped before tests because the newly locked `stackprof` gem was missing locally. `bundle install` installed it; the second invocation passed. The first container full gate found the Zeitwerk mismatch above and was rerun after the repair. No failing test or warning was waived. The container had three expected pending live-broker examples; the host had four because the OTel-dependent live trace-context case was also pending under its environment. The browser seed task skipped because domain data already existed; each browser scenario created its own auction and passed.

The runtime smoke followed the CI commands: `smoke-kafka`, `smoke-api`, `auction_closer --once`, `smoke-concurrent-bids`, `smoke-proxy-bidding`, `idempotency:prune`, plus scheduler and publisher one-shots. Kafka smoke reported three events; the sequential API smoke closed its auction; concurrent and proxy scripts reported success. No hot benchmark was repeated after the Zeitwerk namespace repair because its focused, full and live correctness gates passed and it did not alter request logic. The final OTel-on setting is local Compose configuration, not a committed production default.
