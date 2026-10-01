# Phase 14 final gate logs

2026-10-01, local host, source revision `e3fed47` plus the documented
`scripts/check` Redis isolation change before its final commit. Commands ran
against the existing healthy Compose stack and local Ruby 4.0.6 / Node
24.20.0. The logs are retained as execution evidence, not benchmark results.

| Gate | Exact command or method | Result | Log |
|---|---|---|---|
| Initial full gate | `scripts/check` | 439 examples, 11 Redis projection failures; frontend was not reached | `check.log.gz` |
| Isolation diagnosis | `REDIS_URL=redis://127.0.0.1:6379/15 RAILS_ENV=test bundle exec rspec spec/integration/auction_projection_reconciliation_spec.rb spec/integration/auction_projection_reconciliation_live_spec.rb spec/integration/reconciliation_lease_spec.rb` from `apps/api`, with root `.env` sourced | 24 examples, 0 failures, 2 pending | `reconciliation-isolated.log` |
| Final full gate | `scripts/check` | 439 examples, 0 failures, 4 pending; 73 frontend tests, lint/format/types/build pass | `check-isolated.log.gz` |
| Dependency audit | `bin/bundler-audit` from `apps/api` | No vulnerabilities found | `bundler-audit.log` |
| Compose health and jobs | `docker compose config --quiet`, HTTP `/up` and web GET, Redis ping, Kafka topic describe, one-shot reconciliation and both publishers, `docker compose ps` | Passed; services healthy or running | `compose-smoke.log` |
| Live runtime | `docker compose exec -T api ruby < scripts/smoke-kafka`, `smoke-api`, one-shot closer, `smoke-concurrent-bids`, `smoke-proxy-bidding`, `bin/rails idempotency:prune` | Passed; zero expired records pruned | `runtime-smokes.log.gz` |
| Real browser | `PLAYWRIGHT_CHROMIUM_EXECUTABLE=/usr/bin/google-chrome npm run test:e2e` from `apps/web` | 7 passed | `browser.log` |

The initial and final full-gate commands read root `.env` through
`scripts/check`. The initial failures arose because the live Compose
projection consumer wrote Redis DB 0 while local RSpec generated overlapping
test auction IDs. The isolated focused rerun and final complete rerun passed.
The fix changes only the local test endpoint, not application runtime behavior.
