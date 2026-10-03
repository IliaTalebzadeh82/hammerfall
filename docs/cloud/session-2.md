# Phase 19 Session 2 — managed-service integration contracts

Date: 2026-10-03. Starting commit: `b3b07744d7ebec6fd31c9dbb52d8993c4565be7b`. Status: implementation and local/static proof complete; Phase 19 remains active. No GCP login, project mutation, apply, secret creation, paid resource or GKE command occurred. `PASS STATICALLY` means manifests/provider schema/mock plans or application configuration passed locally. `DEFERRED LIVE PROOF` identifies behavior that requires an authorized GCP environment; it is not an error hidden by a test.

## Kafka — PASS STATICALLY; DEFERRED LIVE PROOF

| Contract | Session 2 result |
| --- | --- |
| Current local | Ruby `rdkafka` uses `bootstrap.servers`; publisher is idempotent and consumers manually store/commit offsets. Local Compose remains PLAINTEXT. |
| Cloud | Managed Kafka requires TLS, SASL/OAUTHBEARER and `roles/managedkafka.client` for connecting; Kafka ACLs authorize topic/group/cluster operations separately. [Google authentication](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/authentication-kafka), [ACLs](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/access-control-kafka-acls). |
| Code/config | `KafkaClientConfig` supplies one local or `google_oidc` config to publisher, audit and projection. Cloud config forces `SASL_SSL`, broker certificate and hostname verification, OAUTHBEARER OIDC and a loopback token endpoint. Google's [non-Java helper](https://github.com/googleapis/managedkafka) is vendored at commit `96b82c8e6db506515a6751660f71c346e89664cb`; its script SHA-256 is `2fd08a1be5d78944250fac731708612d29064cb461015629fa71b27a08d3c2e0`. Each Kafka pod includes a helper sidecar; Google ADC uses GKE WIF, no JSON key or static token. |
| Local behavior preserved? | Yes: topic, partition key, event identity, publisher delivery outcome, audit/projection groups, manual offsets, DB effect before commit and duplicate handling code were not changed. |
| Secret/identity | Three linked KSAs/GSAs give stable `User:<email>` ACL principals for publisher, audit and projection. Each receives connect IAM. The publisher has topic WRITE and cluster IDEMPOTENT_WRITE; consumers have topic READ and their own group READ. Wildcard ACLs with an unbound sentinel account avoid Managed Kafka's allow-when-no-ACL behavior. Neither IAM connect nor broker discovery alone grants all topic operations. |
| TLS/failure | TLS is mandatory in cloud config. Missing bootstrap/token endpoint raises before client creation; token, broker or ACL failure leaves outbox retryable and consumers lagging while PostgreSQL remains authoritative. Error logs contain classes and event metadata, not credentials. |
| Tests/static | `KafkaClientConfig` specs cover local/default, secure cloud config and missing/invalid settings; 41-example local Compose run included Kafka outbox integration. Terraform provider 8.5.0 mirror validates the gated cluster, topic, ACL and IAM HCL; 2 module and 4 root mock runs passed. The managed Kafka API is enabled only with `enable_kafka=true`. |
| Unverified live | WIF-to-GSA token exchange, helper/librdkafka token refresh, actual broker handshake, ACL operation names/enforcement, DNS, sidecar restart and Kafka failure recovery. |
| Decision | Gated Google Managed Kafka remains the faithful target. `enable_kafka=false` by default; no Pub/Sub substitution. |

Google's GKE WIF path has a documented minimum GKE version for direct KSA credentials. The reference uses linked GSAs to obtain stable ACL email principals and still depends on short-lived WIF credentials. The helper image is source-pinned but must be built, scanned and deployed by immutable digest under a later authorized release. The three `unused` OIDC client-field strings are librdkafka-required placeholders that Google's local helper ignores; they are not authentication secrets.

## Redis — PASS STATICALLY; security limitation; DEFERRED LIVE PROOF

| Contract | Session 2 result |
| --- | --- |
| Current local | Redis projection and Sidekiq use local `redis://`; Redis is derived state and a queue, never auction authority. Action Cable uses the PostgreSQL adapter in production, so it has no separate Redis client. |
| Cloud | Classic Memorystore for Redis behind private VPC with in-transit TLS. [TLS](https://docs.cloud.google.com/memorystore/docs/redis/about-in-transit-encryption) needs the instance CA. [AUTH](https://docs.cloud.google.com/memorystore/docs/redis/about-redis-auth) is supported, but provider-computed `auth_string` would be in Terraform state if enabled. Redis Cluster IAM is not a drop-in Sidekiq topology ([Sidekiq guidance](https://github.com/sidekiq/sidekiq/wiki/Using-Redis)). |
| Code/config | `RedisConnectionConfig` centralizes Sidekiq client/server and projection settings. Local mode keeps existing URL behavior. Cloud mode requires `rediss://`, a readable CA and peer verification; optional `auth` reads a mounted password file. The overlay explicitly uses `REDIS_AUTH_MODE=none`. Kafka publisher/audit pods disable unused Redis access. |
| Local behavior preserved? | Yes: projection conflict/order logic and Sidekiq queue semantics are untouched. |
| Secret/identity | Redis CA bundle has separate Secret Manager metadata and is mounted only by API, worker and Kafka projection. No Redis password or generated AUTH value is in Terraform, Git or logs. No application-layer Redis authentication is claimed for this reference. |
| TLS/failure | Invalid URL/CA/auth config fails clearly. Redis outage delays Sidekiq/projection; PostgreSQL truth remains. Private TLS without AUTH is an explicit security limitation; `enable_redis=false` remains default and requires a decision before any deployment. |
| Tests/static | Config specs cover local, TLS, missing CA/auth and redacted errors; Compose run included Redis projection integration. Terraform/mock tests prove the default gate. |
| Unverified live | Memorystore CA chain, client handshake, private networking, failover and secure AUTH bootstrap alternative. |
| Decision | Keep classic Memorystore; do not silently switch to Cluster or put `auth_string` in Terraform state. |

## Cloud SQL and Rails secrets — PASS STATICALLY; DEFERRED LIVE PROOF

| Contract | Session 2 result |
| --- | --- |
| Current local | Rails connects directly to PostgreSQL via `DATABASE_URL`; PostgreSQL transactions/locks/clock remain the sole authority. Compose secrets and local URL remain valid. |
| Cloud | Cloud SQL PostgreSQL 18 private PSA IP, encrypted-only connections and shared CA. [Google SSL guidance](https://docs.cloud.google.com/sql/docs/postgres/configure-ssl-instance) calls for the PSA DNS hostname plus `sslmode=verify-full` and a CA bundle. Terraform models private DNS, automatic server certificate rotation and deletion protection. |
| Code/config | `SecretFiles` loads `DATABASE_URL_FILE`, `SECRET_KEY_BASE_FILE`, optional `RAILS_MASTER_KEY_FILE` at Rails boot, removing one terminal newline. `DATABASE_CONNECTION_MODE=cloud_sql` rejects non-PSA hostnames, missing CA, weaker TLS mode and duplicate query keys. The app uses direct libpq; no proxy or IAM DB login was introduced. |
| Local behavior preserved? | Yes: no auction command, pool, transaction, lock, deadline or schema semantics changed. Production Rails boot with a dummy mounted key passed locally. |
| Secret/identity | Terraform owns instance/database, four Secret Manager containers and per-KSA accessor grants; it owns no SQL user, password or secret version. A future restricted bootstrap creates the app login and versions. GKE CSI mounts files read-only. Rails needs `SECRET_KEY_BASE`; this repository has no encrypted credentials file, so a master key alone did not boot. |
| TLS/failure | TLS mode and CA path are checked at boot; libpq performs actual chain/hostname verification on connection. SQL outage stops authoritative commands and `/ready`, without fallback to Redis/Kafka. A missing CSI file stops affected pod startup. Existing pod behavior during a Secret Manager outage depends on mounted data/cache and is unproven. |
| Tests/static | Boot helper specs cover unchanged local env, mounted values, missing/conflict, verified URL and duplicate keys. Compose integration passed. Dummy production `rails runner` boot passed; it did not connect to Cloud SQL. Terraform mirror validation and mock plans passed. |
| Unverified live | Actual shared CA chain, private DNS, SSL negotiation/hostname check, secret CSI versions, password bootstrap, SQL grants, DB migration and failure recovery. |
| Decision | Direct PostgreSQL with verified TLS; no password in tfvars/state. See [overlay bootstrap](../../k8s/overlays/gcp/README.md). |

## GKE workload, identity and edge — PASS STATICALLY; DEFERRED LIVE PROOF

| Contract | Session 2 result |
| --- | --- |
| Current local | Phase 18 base uses selectorless dependency Services and a web Nginx proxy sidecar. API and web share a local origin. |
| Cloud | GKE Autopilot pods use KSAs, GKE Secret Manager CSI and immutable Artifact Registry digests. Global external Gateway terminates HTTPS via Certificate Manager map, redirects HTTP, routes `/api` and `/cable` to API and `/` to web, and checks `/ready` for API. [Gateway](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways), [CSI](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component). |
| Code/config | A Kustomize overlay removes local dependency Services, proxy and DB Secret ref, mounts read-only CSI volumes, sets cloud env and WIF KSAs, adds Kafka helper only to Kafka pods and keeps `db-prepare` suspended. `render.py` requires domain, certificate map, static IP, private service endpoints and three digests. |
| Local behavior preserved? | Base manifests are unchanged except a new `kustomization.yaml`. Local Compose integration passed; base and overlay both render. Full kind regression is a final Session 3 gate. Web continues same-origin HTTP/WSS from browser; Rails origin/host settings use public hostname. |
| Secret/identity | Web has no GCP IAM or secret mount. Six Rails role KSAs, including db-prepare, match Terraform readers; Kafka roles have linked GSA annotations. No JSON key or payload is embedded. |
| TLS/failure | HTTPS/WSS at the edge and HTTP redirect are modeled. Private services are not exposed by Gateway routes. `/ready` checks DB availability; `/up` is not the external API health signal. Failed mounts or image pulls prevent affected pods from starting. |
| Tests/static | `kubectl kustomize` base and overlay passed; overlay validator checked 28 resources, identity, mounts, routes, health and local-only removals. Dummy render output had 28 resources and no placeholders. No GKE CRD admission was attempted. |
| Unverified live | Gateway controller/Certificate Manager admission, DNS, public TLS, WebSocket upgrade/timeout, actual WIF and CSI, GKE Autopilot effective requests, image pull, rollout and outage behavior. |
| Decision | GCP overlay is static and non-applied. A real domain/certificate map/IP and release digests remain inputs. |

## Cost, connections and evidence

[Cost model](cost-estimate.md) now accounts for three auth sidecars, removal of two Nginx sidecars, GKE Autopilot minimum/default requests, private DNS and HTTP+HTTPS edge. Eleven running pods request 1.25 vCPU/2.1875 GiB before Autopilot adjustment; a nonburst general-purpose floor would be about 2.75 vCPU/5.5 GiB plus default 14 GiB ephemeral storage across fourteen containers. Theoretical Rails pool ceiling is 27 steady, 54 with all seven background rollouts plus API surge and db-prepare, and about 70 including operator and headroom; no cloud usage was measured. Google's public [Kafka pricing](https://cloud.google.com/managed-service-for-apache-kafka/pricing) was checked on 2026-10-03, but an `europe-west4` quote remained unavailable; the Iowa illustration leaves Kafka visibly separate and costly.

| Check | Result | Limit |
| --- | --- | --- |
| Docker Compose focused RSpec: Kafka/Redis/secret config and Kafka outbox/Redis projection integration | **PASS:** 41 examples, 0 failures, 1 pre-existing live-broker pending; seed 46442 | Local services only. |
| RuboCop changed Ruby/spec files | **PASS:** 12 files, 0 offenses | Focused lint. |
| Dummy production Rails boot with mounted `SECRET_KEY_BASE_FILE` | **PASS:** `production_booted` | Dummy DB URL, no SQL connection. |
| Terraform 1.16.5 `fmt`, both roots/module `validate`, mock `test` | **PASS STATICALLY:** root 4 and module 2 passed | Provider 8.5.0 checksum-verified OpenTofu mirror; official distribution geoblocked; no ADC or provider-backed plan. |
| `kubectl kustomize` base/overlay and `validate.rb` | **PASS STATICALLY:** 28 overlay resources | No GKE admission or CRDs. |
| GCP connectivity, paid services, cloud failure/restore | **DEFERRED LIVE PROOF** | No cloud mutation or spend authorized. |

## Adversarial findings and next session

The review fixed a Kafka sentinel service-account name that exceeded Google's 30-character bound for longer environment names, moved Managed Kafka API enablement behind its own gate, and rejected duplicate Cloud SQL TLS URL keys. It also found the production key requirement through a failed dummy boot, then verified the repaired file mount path. No service-account JSON, static access token, Terraform secret payload/version, permissive Redis AUTH claim, public stateful listener, Phase 20 auth feature or changed auction business rule was introduced. The intentional Redis no-AUTH limitation and all live-cloud gaps remain visible.

Session 3 should run final broad backend/frontend, Compose and relevant kind regression; verify Terraform against official provider where accessible and run remaining static/security gates; resolve any integration defects and reconcile final docs/CI. A provider-backed read-only plan and actual GCP behavior require a separately authorized environment; paid apply remains prohibited. Phase 19 is not complete.
