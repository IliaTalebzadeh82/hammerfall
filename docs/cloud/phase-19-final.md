# Phase 19 final review — Terraform and GCP reference

Date: 2026-10-03. Status: local/static verification complete; no GCP authentication, API mutation, resource or charge. This is Hammerfall's **near-deployable reference**, not a production deployment or a description of Catawiki's internal infrastructure. Detailed architecture and research are in [ADR-015](../adr/015-gcp-reference-infrastructure.md), [architecture](architecture.md), [cost model](cost-estimate.md) and [Session 2](session-2.md).

Hosted [GitHub Actions run 37105296963](https://github.com/IliaTalebzadeh82/hammerfall/actions/runs/37105296963) passed API, web and Compose jobs on the Phase 19 closure commit `a1fca5e0bf6055e5351b52437772e33ec9053ee0`, including the hosted browser scenarios. Normal CI used no GCP credentials.

## Direction and ownership

The public [Catawiki engineering page](https://catawiki.careers/engineering) confirms GCP and Kubernetes; a [platform vacancy](https://catawiki.careers/vacancies/platform-engineer-portugal-3270914-8219279) names Terraform or Ansible as relevant experience. That makes GCP a relevant target for this portfolio reference, while its managed services support the repository's existing PostgreSQL/Kafka boundaries. Terraform gives the cloud resource graph a reviewable, repeatable declaration with explicit cost gates and protected state. The evidence does not confirm Catawiki's region, GKE mode, database, cache, broker, Gateway or Terraform estate. Hammerfall chooses these as an engineering reference: one `europe-west4` project, private GKE Autopilot nodes, Cloud SQL PostgreSQL 18, Classic Memorystore Redis, Google Managed Service for Apache Kafka, Artifact Registry, Secret Manager and an external Application Load Balancer through GKE Gateway. Autopilot reduces node operations; Cloud SQL retains the PostgreSQL transaction and lock authority. Redis is derived projection/Sidekiq state. Kafka remains Kafka because the application's partitions, outbox, consumer groups and offsets are real contracts; Pub/Sub would require an application migration.

Terraform owns the VPC/NAT/PSA, GKE, Cloud SQL/private DNS, registry, secret *metadata*, IAM and separately gated Redis/Kafka. Kubernetes owns Deployments, Services, KSAs, CSI mounts, Gateway/HTTPRoutes and health policies. The default Terraform root makes **zero resources/API changes**; `enable_reference_infrastructure`, a project and bounded operator CIDR are required. `enable_redis` and `enable_kafka` are independent false-by-default gates. A GCS backend with versioning, public access prevention and narrow IAM must be separately bootstrapped before any real use; Terraform state remains sensitive even when CLI output is redacted.

State would contain project/network identifiers, GKE endpoint/cluster metadata, Cloud SQL private IP/DNS/certificate metadata, Redis endpoint/CA metadata when enabled, Kafka broker/topic/ACL/IAM identities when enabled, and Secret Manager names/IAM policies. The reference creates no SQL user/password, Secret Manager secret version or Redis `auth_string` in Terraform. If classic Redis AUTH were enabled through the provider, its generated string would enter state despite a sensitive CLI display; this is why AUTH is not modeled as a Terraform-managed value. Restrict and version both reference and bootstrap state.

## Application contract

| Boundary | Implemented design | Live gap |
| --- | --- | --- |
| Cloud SQL | Private PSA DNS `*.sql-psa.goog`, mounted CA, libpq `sslmode=verify-full`; duplicate/weak TLS parameters fail boot. SQL credentials and secret versions remain outside Terraform. PostgreSQL alone decides bid, deadline and winner. | Real DNS, chain/hostname handshake, failover and connection ceiling. |
| Kafka | Ruby/librdkafka uses SASL_SSL/OAUTHBEARER and Google's loopback ADC helper in each Kafka pod. WIF links three KSAs to separate GSAs. IAM permits connection; explicit topic WRITE/READ, publisher idempotent WRITE and group READ ACLs authorize operations, with sentinel wildcard baseline. No JSON key or static token. | WIF exchange, broker OAuth/ACL enforcement, helper recovery and managed transport. |
| Redis | Local `redis://` remains ordinary Compose mode. Cloud mode requires `rediss://`, readable CA and peer verification. Classic Memorystore is private/TLS with **no application AUTH**, disabled by default; it must not be enabled as a production-secure reference without a separate authentication decision. | Live TLS/failover and an acceptable authentication design. |
| Secrets/identity | Four Secret Manager metadata containers; external bootstrap supplies URL/key/SQL CA/Redis CA versions. Read-only CSI mounts are selected by workload. Web has no secret or GCP role; the closer has database-only KSA/mount; Redis consumers receive its CA. Kafka GSAs have narrowly linked identities. | Actual CSI mount, rotation, SQL app-user bootstrap and token exchange. |
| Edge/images | HTTP redirects to HTTPS; `/api/*` and WSS `/cable` reach Rails, `/` reaches web. API backend health uses PostgreSQL-backed `/ready`; `/up` remains liveness. Cloud images require Artifact Registry SHA-256 digests. | GKE admission, named address/certificate/domain, public TLS/WSS and image pulls. |

## Local and static evidence

- Backend: **461 examples, 0 failures, 3 expected live-broker pendings**, seed **45789**. RuboCop inspected 138 files with zero offenses; Brakeman found zero warnings; bundler-audit found no vulnerabilities; Zeitwerk and Ruby syntax passed.
- Frontend: lint, format, typecheck and production build passed; Vitest **74 tests in 10 files**, zero failures.
- Compose: `up --build --wait` reached health; API `/up` and `/ready`, web, PostgreSQL, Redis and Kafka responded. Sidekiq/scheduler and publishers ran; the real broker smoke proved three public events, audit and projection flow. The sequential API smoke exercised bids, rejection and closure. Local environment URL/Redis/Kafka modes were used.
- Kind base: the first apply uncovered `up.sh` trying to apply `kustomization.yaml` as a cluster resource. The script was repaired and its rollout rerun. Two API, two web and seven background pods became ready; `db-prepare` completed, the API lifecycle smoke passed through the web Service, and a deleted API pod was replaced while PostgreSQL auction state remained readable. Compose stateful services remained external. Base render has 17 resources and no GCP dependency.
- GCP overlay: **29 resources** rendered with explicit dummy deployment inputs. Static validation checks nine Deployments, KSA/Terraform identity names, per-workload secret class, Kafka helper, private dependency removal, Gateway route intent and `/ready` health. Rendered images use supplied digests; no placeholder values, local Nginx sidecar or Compose dependency Service remained.
- Terraform 1.16.5: format passed; reference, module and bootstrap `init -backend=false`/`validate` passed using the official Google 8.5.0 release ZIP checked against its lock-file SHA-256 and installed in a temporary mirror. Registry discovery itself was inaccessible. Credential-free mock tests passed **4 root + 3 module**, zero failures, including zero-resource default and independent Redis/Kafka gates. No provider-backed project plan or apply ran.
- Tracked-file credential scan found no private keys, JSON service-account credentials, payload versions, Terraform state or committed CA/key files. Test fixtures contain dummy credential strings only. Normal CI requires no GCP credential.

## Cost and capacity boundary

The [cost model](cost-estimate.md) covers GKE effective requests, Cloud SQL compute/storage/backup, Redis, Kafka, Gateway/load balancer, NAT, Artifact Registry, Secret Manager, DNS/GCS state, logging/monitoring and egress. The cloud overlay requests 11 pods/14 containers, **1.25 vCPU and 2.1875 GiB** before possible Autopilot minima and ephemeral-storage defaults. These are manifest totals, not admission or sizing results. With pool size three, `2 API × 3 + 7 background × 3 = 27` steady theoretical connections; migration and simultaneous rollout can reach **54**, motivating about **70** with operator connections and headroom. Scaling/HPA must account for this budget.

The Iowa-only full-stack arithmetic is about **$594/month before major variable charges**, including about **$248/month** for a minimal illustrative managed Kafka shape. No verified `europe-west4` Kafka quote exists; Kafka remains a separate economic decision. The disabled default is the only established zero-cost configuration. No monthly bill or production capacity was measured.

## Final adversarial findings

| Severity | Finding and disposition |
| --- | --- |
| Critical | None found in the static/local Phase 19 review. |
| High | No open High finding. The base kind apply regression was repaired and rerun. No cloud service gained auction authority; no public stateful endpoint or secret payload in Terraform was found. |
| Medium | Classic Redis has private TLS but no AUTH. Its independent gate remains off; enabling it requires a new security decision. Static CSI/WIF/Kafka ACLs/Gateway cannot prove live enforcement. |
| Low | The closer initially shared the Redis-capable worker identity/mount; now it has a database-only KSA and CSI class. |
| Future | Real project provider plan, GKE admission, IAM token exchange, secret rotation, managed-service connections, Gateway TLS/WSS, zone/region failure, restore/DR, production sizing, HPA and actual cost. |

Network exposure is modeled at the Gateway only; SQL/Redis/Kafka use private connectivity. The GKE control endpoint uses a bounded operator CIDR and private nodes need NAT; real VPC firewall and DNS behavior require project review. Runtime IAM has no owner/editor role, and normal CI has no deployment identity. Mounted secret versions are read-only and secrets are not logged by the new guards. Cloud SQL retains deletion protection, backups and PITR, but no restore proof. Pod/node, SQL, Redis, Kafka, secret-mount, zone and region failures are described as designed behavior in the [architecture](architecture.md), never as GCP experiments.

## Before any authorized deployment

Obtain spending approval and a Netherlands quote; choose a project, domain, certificate map, static IP and immutable built image digests; review Redis authentication; bootstrap protected GCS state and SQL app credentials/Secret Manager versions outside Terraform; run a credentialed provider-backed plan; validate GKE admission, WIF/CSI, SQL verify-full DNS/TLS, Redis TLS, Kafka OAuth/ACLs, Gateway HTTPS/WSS, capacity/connection limits, backups/restore and failure recovery. No GCP authentication, apply or managed-service connectivity was part of Phase 19.
