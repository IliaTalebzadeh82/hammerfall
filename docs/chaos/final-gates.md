# Phase 16 final verification gates

Local date: 2026-10-02. Starting SHA:
`e868bc41138a837b60d8de404781ba6497e26d4b` (clean). The normal Compose
stack was rebuilt and force-recreated from source with `docker compose up -d
--build --force-recreate --wait --wait-timeout 360`; all required services
became healthy or running. No Compose service had a chaos environment variable,
the new API container had no crash marker, and `docker compose config --quiet`
passed. The earlier Session 2 one-shot marker was erased by recreation.

| Gate | Result |
| --- | --- |
| `scripts/check` | Passed: RuboCop 129 files/0 offenses; Brakeman 0 errors/0 warnings; Zeitwerk passed; backend 449 examples/0 failures/3 expected pending; web lint, format, typecheck, 73 Vitest tests and production build passed. |
| Focused boundary regression after one-shot hook hardening | `rspec spec/integration/kafka_outbox_spec.rb spec/requests/idempotency_spec.rb spec/services/chaos_crash_spec.rb`: 46 examples/0 failures/1 gated live-broker pending; targeted RuboCop and Ruby syntax passed. |
| Security and evidence hygiene | `bin/bundler-audit`: no vulnerabilities; Python chaos scripts compiled; `git diff --check` passed. Retained artifacts were scanned for raw keys/fingerprints/private ceilings/priorities, credentials, headers, tokens and connection strings. One pre-existing test log's local Redis URL was redacted. |
| Real Chrome, normal suite | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e`: 7 passed, 1 opt-in chaos test skipped. This includes cross-client Cable/REST, soft close, final winner and response-loss browser scenarios. |
| Real Chrome, worker outage | `PHASE16_CHAOS_BROWSER=1 PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npx playwright test e2e/realtime.spec.ts --grep 'REST recovers a bid'`: one scenario passed twice, including after its cleanup guard was tightened. Final fixture auction 567 advanced public revisions 2→3→4, with explicit REST recovery during outage and a later Cable-hint REST recovery. |
| Compose runtime | API `/up`, web redirect, Redis PONG, Kafka topic (3 partitions), scheduler and both publisher one-shots, Kafka end-to-end (3 events), sequential auction API lifecycle, independent closer one-shot, concurrent HTTP bids, proxy bidding and idempotency prune (0 expired) passed. |
| Broad backend after hook hardening | `RAILS_ENV=test bundle exec rspec` with isolated Redis DB 15: 449 examples/0 failures/3 expected pending. |
| Fresh Compose after hook hardening | Rebuilt and force-recreated all services from final source: required services healthy/running; no API `/tmp/hammerfall-chaos-*` marker, no `HAMMERFALL_CHAOS_*` variable in application services, no `chaos_crash` log. A new Kafka end-to-end smoke passed (auction 566, revision 3, 3 events). |
| Hosted CI | Pending closure push and required API, web and Compose jobs. |

The first focused invocation omitted the local PostgreSQL credentials and
failed before loading examples. Re-running with the repository's `.env` and
isolated test Redis DB 15 passed; no test or invariant was changed to hide it.
OpenTelemetry export errors in the host test process were telemetry transport
noise; the suite passed and direct state remained the correctness evidence.
