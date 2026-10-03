# Phase 20 final review — Identity & Security

Status: local final gate passed on 2026-10-04; closure requires the hosted `CI` run on this report's commit to pass. Phase 21 has not started.

## Implemented boundary and guarantees

- First-party bcrypt credentials issue opaque, revocable PostgreSQL sessions. The browser receives an encrypted, HttpOnly, host-only, SameSite=Lax cookie and uses a separate same-origin CSRF header. PostgreSQL time controls the fixed 12-hour expiry; logout deletes the row. New Cable handshakes and subscriptions require a live row.
- HTTP commands derive the actor from that session. Supplied `bidder_id` is rejected. Public reads remain public; a seller owns draft management and eligible cancellation, while an operator performs lifecycle transitions. The locked auction model and database constraints reject seller leadership/winning even if a stale caller races an ownership view.
- Redis shares authentication, bid, lifecycle and Cable admission quotas across Rails replicas. A 429 is a definite pre-command rejection with `Retry-After`. Login and new Cable admission fail closed during Redis loss; existing authenticated bid/lifecycle requests use bounded per-process fallback. PostgreSQL alone still decides price, bid legality, deadline and winner.
- Local nginx and an early Rack guard bound `/api/v1` bodies to 32 KiB before Rails JSON parsing. New idempotency claims store versioned HMAC-SHA256 digests. Retained SHA-256 and previous-key rows remain replayable by the same authenticated actor with the original payload/key. PostgreSQL advisory locking serializes differently versioned claims. A changed payload conflicts; a different actor cannot retrieve another actor's result.
- Cable broadcasts only public `{type, auction_id, revision}` invalidation hints. Public user listing includes only users with public bids and omits credentials and role. Security events use bounded category/outcome/reason fields without actor, IP, login, keys, tokens or private maximums.

The server does not promise that an accepted bid leads, that a Cable hint confirms a command, that a 5xx/network loss means rejection, or that a browser countdown decides closure. A replay returns its historical outcome; a fresh GET supplies current state.

## Final verification

| Gate | Result | Evidence |
| --- | --- | --- |
| Fresh local Compose recreation | Rebuilt images and recreated every service; regenerated shared development Rails secret volume while retaining PostgreSQL data. bcrypt loaded, migrations current, four demo identities present, API A/B, web, PostgreSQL, Redis, Kafka and background roles healthy/running. A/B Rails secret fingerprints matched. | `/tmp/phase20-compose-rebuild.log`; live health/runner checks |
| Authenticated application smoke | Lifecycle, manual bid, low-bid rejection, close/winner/history, 12-way/equal concurrent bids, proxy bidding, Kafka outbox publication/consumption passed. | `/tmp/phase20-smoke-api.log`, `-concurrent.log`, `-proxy.log`; Kafka CLI output |
| Distributed correctness | Phase 17 A/B script passed sequential, concurrent, equal-ceiling proxy and cross-replica same-key race/replay. Final direct A/B proof passed login A → session B → bid A → replay B → logout B → reject A, plus competing bids across A/B and SQL sequence/price. Ten-way idempotency and stale-closer smokes passed with authenticated HTTP commands. | `/tmp/phase20-cross-replica.log`, `-final-replicas.log`, `-smoke-idempotency.log`, `-smoke-closing.log` |
| Browser | Real Chrome/Playwright via Next rewrite, cookie/CSRF, Rails replicas and Cable: 8 passed, 1 opt-in skipped in full run. The opt-in worker-outage case then passed separately. Covers login/logout, anonymous mutation, seller self-bid, manual/maximum bid, same-user reauthentication and unchanged retry, cross-actor replay isolation, countdown/closure, proxy settlement, soft close and realtime REST recovery. | `/tmp/phase20-final-browser2.log`, `/tmp/phase20-browser-worker-outage.log` |
| Backend | 494 examples, 0 failures, 4 documented gated integration pending, seed 28252, isolated Redis DB 15, pool 15. Focused rotation/concurrency/identity/body cases: 29 examples, 0 failures, seed 11889. | `/tmp/phase20-final-rspec.log`, `/tmp/phase20-final-focused-security.log` |
| Frontend | 76 Vitest tests passed; typecheck, lint, format and production build passed. | `/tmp/phase20-final-web-*.log` |
| Ruby/security static | RuboCop 162 files/0 offenses, Zeitwerk passed, Brakeman 0 warnings, bundler-audit 0 known vulnerabilities. | `/tmp/phase20-final-rubocop.log`, `-zeitwerk.log`, `-brakeman.log`, `-audit.log` |
| Degraded and edge paths | Alternating A/B wrong-login requests produced five 401 then a shared 429. With Redis stopped, new login returned 503, a prior session remained valid, its bid committed under local fallback and new Cable was unavailable; Redis recovered healthy. A 33,052-byte POST through Next returned 413 JSON. | `/tmp/phase20-final-limiter.log`, `-redis-outage.log`, `-cable-outage.log`; live edge probe |
| Cloud static | Base and GCP overlays rendered; validator checked 29 GCP resources, secret mounts, routes and health. Dummy render/validator passed. Terraform was unavailable locally; no GCP apply or paid resource occurred. | `/tmp/phase20-k8s-base.yaml`, `-k8s-gcp.yaml`, `-gcp-rendered.yaml` |
| Hosted CI | Required on the exact closure commit; the run ID, SHA and job results are reported in the final closure response after verification. | GitHub Actions run/job records |

The closure commit cannot literally contain its own content hash or a future Actions run ID. The authoritative exact values are the commit containing this report and its completed `CI` run; they are reported together in the final closure response.

The first hosted attempt (`6c38b59`, run `37158321874`) passed its web and full Compose/browser jobs, but its API RSpec step failed. The API job used the default five database connections for ten-worker idempotency cases. Four focused cases timed out locally with that default; the same 16 focused examples passed after setting `RAILS_MAX_THREADS=15`. The final repair revision must pass the complete hosted workflow.

## Adversarial findings

| Severity | Finding and resolution or accepted limit |
| --- | --- |
| Critical/High | None found in phase scope after the final tests and review. This is not a professional penetration test. |
| Medium, fixed | The old smoke/browser clients used removed actor selection. They now use seeded credentials, cookie persistence, CSRF and explicit keys. A local hardcoded `localhost` Cable URL dropped host-only cookies when Playwright used `127.0.0.1`; the default now follows the browser host and the full browser suite passed. |
| Medium, accepted | The GKE Gateway's upstream byte buffering limit and live cloud secret rollout are unverified. The Rails parser is bounded, but earlier components may buffer. Cloud remains a reference, not a deployed production service. |
| Medium, accepted | HMAC lookup assumes every active replica uses byte-identical material for a given key ID. The static cloud reference mounts one Secret Manager version, but no live cross-replica drift detector exists. A same-ID/different-secret misconfiguration could miss a retained retry even though the advisory lock serializes requests. Release operations must verify one keyring and drain old code before writes. |
| Low, accepted | During Redis loss, switching replicas can multiply the per-process fallback quota. This degrades abuse control, never auction correctness. A socket established before expiry/revocation may continue receiving public invalidation hints until disconnect; a private Cable payload would require a new revocation design. |
| Informational | Local security logs and metrics require deployment-specific access/retention policy. No durable audit table or professional penetration test is claimed. Historical earlier-phase chaos/load scripts that still target the retired actor API are not current Phase 20 smoke/CI gates and require migration before reuse. |

Review checked alternate `bidder_id` input, owner/operator paths, locked seller check and database constraints, actor-scoped replay and key retention, cross-replica secrets, limiter admission ordering, body rejection, `/users`, public presenters, Cable payload, bounded events and representative runtime logs. Runtime API logs contained 380 security-event rows and zero matches for the local demo password, raw cookie pair, CSRF or idempotency headers, unfiltered demo login bind, or JSON private maximum values. Those searches are a local sample, not a general log-retention guarantee.

## Phase 20 definition of done

| Requirement | Implemented and verified | Evidence | Remaining limit |
| --- | --- | --- | --- |
| Actor identity across HTTP, browser and Cable; expiry, revocation, CSRF | Yes | identity/Cable specs, full browser, A/B proof | Established sockets may receive public hints until disconnect. |
| Buyer/seller/operator/background capabilities and private maxima | Yes | owner/model/spec matrix, seller browser, domain smokes, public representation review | Additional marketplace policies belong to Phase 21. |
| Shared abuse bounds and unavailable limiter policy | Yes | rate-limit specs, A/B shared quota, Redis outage | Fallback quota is per process. |
| Early body bound and streamed/declared input tests | Yes | Rack/request specs and Next edge 413 | GKE Gateway buffering unproven. |
| HMAC digest migration, rotation, legacy replay and multi-instance safety | Yes | ADR-017, PostgreSQL focused/full suites, A/B replay | Old executors must be drained before new HMAC writes; retained key IDs cannot be removed early. |
| Bounded security events and public-data filtering | Yes | event/representation specs, runtime log sample | Production log access/retention requires deployment policy. |
| Final regression, static checks and local startup | Yes | table above | No live production/cloud deployment. |
| Hosted closure CI | Required on exact closure SHA before declaring completion | GitHub Actions run/job records and final closure response | Do not declare closure if red. |

## Operational limits and rollout

Production replicas must receive the same `SECRET_KEY_BASE` and validated HMAC keyring. ADR-017's initial rollout drains old executor code before any HMAC-version write; mixed old/new writer compatibility is not claimed. A previous key remains configured until all rows using it are physically pruned. The local shared secret volume is development-only. No live cloud deployment, professional penetration test, proven GKE Gateway buffering limit, production backup/restore or Phase 22 operational exercise occurred. Phase 21 marketplace trust and policy expansion has not started.

Phase 20 is complete when the hosted `CI` workflow passes with `head_sha` equal to the commit containing this report. The final closure response records that run and commit together.
