# Phase 19 GCP reference architecture

Research date: 2026-10-03. Design only; zero GCP resources created. [ADR-015](../adr/015-gcp-reference-infrastructure.md) records the adopted choices. This is Hammerfall's reference design, informed by public Catawiki stack evidence, not a description of Catawiki's internal infrastructure.

## Evidence boundary and option comparison

**Catawiki publicly confirmed:** its [engineering page](https://catawiki.careers/engineering) says it runs a Kubernetes orchestrated microservice architecture on GCP. A [platform role](https://catawiki.careers/vacancies/platform-engineer-portugal-3270914-8219279) lists Kubernetes/cloud experience and Terraform or Ansible. These do not identify GKE mode, region, stateful services, IAM or how much infrastructure is Terraform-managed.

**Hammerfall decision:** one `europe-west4` reference project, Autopilot, private Cloud SQL, private Redis, a managed-Kafka target and Google edge. Netherlands is plausible for a European demonstration and appears in the current [GKE pricing region list](https://cloud.google.com/kubernetes-engine/pricing), [Redis locations](https://docs.cloud.google.com/memorystore/docs/redis/instances), and [managed Kafka locations](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/locations). Cloud SQL is available there on its [pricing page](https://cloud.google.com/sql/pricing). This does not imply Catawiki uses the Netherlands. Another region changes service rates, latency, residency and available zones/features; re-evaluate all before use.

| Option | Architecture | Decision |
| --- | --- | --- |
| A | GKE Autopilot + Cloud SQL + Memorystore + managed Kafka | **ADOPT as reference target.** Managed nodes, native Kafka protocol and private managed state. Broker/auth and cost still gate deployment. |
| B | GKE Standard + same managed dependencies | **DEFER.** More node control/debugging and possible high-utilization savings, with node operations and whole-node billing. No observed requirement yet. |
| C | Autopilot + Cloud SQL/Redis + Pub/Sub | **REJECT as infrastructure substitution.** It needs an app migration of partition/consumer-group/offset semantics, not a Terraform flag. |

Autopilot bills general-purpose workloads by effective pod requests, may increase low requests, and manages node lifecycle. Standard bills whole nodes and gives more control over node pools. Both have a [$0.10/cluster-hour management fee](https://cloud.google.com/kubernetes-engine/pricing), subject to billing-account free credits. Background workers and long-lived Kafka consumers are ordinary pods; their correctness still comes from PostgreSQL locks, idempotency, outbox, receipts and leases. [Autopilot request rules](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests) require validation of all Phase 18 requests before a real rollout. No HPA or PDB is claimed from the one-node local proof.

## Responsibility and traffic

```mermaid
flowchart TD
  I[Internet] --> E[External HTTPS Application Load Balancer<br/>TLS and WSS edge: planned]
  E --> G[GKE Gateway and HTTPRoutes: planned]
  G --> W[Web pods]
  G --> A[Rails API and Action Cable pods]
  W --> A
  A --> P[(Cloud SQL PostgreSQL<br/>AUTHORITATIVE auction state)]
  A --> R[(Memorystore Redis<br/>DERIVED projection and Sidekiq)]
  A --> K[(Managed Kafka target<br/>EVENT TRANSPORT)]
  B[Sidekiq, publishers, consumers,<br/>closer and scheduler pods] --> P
  B --> R
  B --> K
  AR[Artifact Registry] --> G
  SM[Secret Manager metadata and versions] --> WI[Workload Identity / secret mount]
  WI --> A
  WI --> B
  O[Cloud Logging / Monitoring<br/>Prometheus and OTel mapping] -.-> G
```

The GKE process set retains two API pods, two web pods, Sidekiq, Sidekiq outbox publisher, Kafka outbox publisher, Kafka audit consumer, Kafka projection consumer, auction closer and reconciliation scheduler. `db-prepare` remains a one-shot migration job before rollout. Terraform owns GCP resources; Kubernetes manifests own these workloads. Phase 18's Nginx sidecar solved local same-origin routing and is not the chosen cloud edge. Gateway can route `/api` and `/cable` to API and other paths to web on one origin. An [external Application Load Balancer supports WebSocket](https://docs.cloud.google.com/load-balancing/docs/https); timeout, routing, TLS, HTTPS redirect, health checks, certificate and domain still need cloud-specific manifests and verification. No certificate, DNS zone or address is provisioned now.

## Network, authority and failure boundaries

The foundation defines one custom VPC, a `10.40.0.0/20` GKE subnet, pod and Service secondary ranges, private Google access, private GKE nodes, a narrow operator CIDR to its public control endpoint, Cloud NAT for outbound fetches, and a `10.48.0.0/16` Private Services Access allocation for Cloud SQL and Redis. There is no public database, Redis or Kafka listener in this design. Cloud NAT, public endpoint exposure and VPC firewall/network-policy behavior must be reviewed with a real project; an operator CIDR is required before enabling the reference module. [GKE private nodes](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation) need an egress path for internet-bound workloads. Managed Kafka uses private VPC subnet endpoints and DNS; it requires authenticated encrypted clients, even though its broker is private ([overview](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/overview), [networking](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/networking-kafka)).

Cloud SQL PostgreSQL 18 matches local Compose's PostgreSQL 18 major; [Cloud SQL currently supports 18](https://docs.cloud.google.com/sql/docs/postgres/db-versions). The Terraform reference sets Enterprise edition explicitly, private IP, encrypted-only client connections, SSD, backups, PITR and both API/Terraform deletion protection. The default is a **zonal** cost-conscious instance; `REGIONAL` is the production-reference HA switch. [Cloud SQL HA](https://docs.cloud.google.com/sql/docs/postgres/high-availability) provides a secondary zone for that service; GKE regional placement does not supply it. The app needs a database user/password bootstrap outside Terraform, TLS verification and Secret Manager delivery. No password or secret version enters Terraform state. Direct private IP avoids a proxy sidecar, but Rails must set `sslmode=verify-full` with a trusted server CA/hostname, which is unresolved. Connection pool budget at Phase 18's 3 connections/process is `2 API × 3 + 7 background × 3 + 1 db-prepare × 3 = 30` during migration; add rollout overlap, console/migration sessions and at least 25% headroom before sizing or HPA. This is a ceiling calculation, not observed connection use. [Cloud SQL connection limits](https://docs.cloud.google.com/sql/docs/postgres/manage-connections) vary by instance.

Redis Basic is the cost-conscious single-zone baseline; Standard HA is a separate option with failover ([tier comparison](https://docs.cloud.google.com/memorystore/docs/redis/memorystore-for-redis-overview)). The reference resource definition is private and TLS-only, but `enable_redis=false` keeps it unprovisioned even when the wider infrastructure gate is enabled. Current Redis clients still use `redis://` and have no CA wiring, so a cloud workload must not be deployed against it yet. Basic Redis AUTH generates a string that Terraform would retain in state; `auth_enabled=false` is an explicit temporary gap with VPC isolation, not a claim of complete Redis security. Evaluate client TLS and an out-of-state auth bootstrap or Redis Cluster IAM auth before enabling it. Redis loss delays Sidekiq and projections; PostgreSQL auction state remains intact.

Kafka's current `rdkafka` producer/consumers configure only `bootstrap.servers`. Managed Kafka requires SASL/IAM or mTLS, TLS, private endpoint DNS and Kafka ACLs. The required adapter and tests must preserve topic partitioning, keyed per-auction ordering, manual offset commits after SQL effects, redelivery and event IDs. Self-hosting a small broker is not a production HA shortcut. A third-party managed Kafka service is an inference/alternative subject to equivalent semantics, private connectivity and cost. Pub/Sub would be an explicit architecture migration. No broker resource is in Session 1 Terraform.

| Failure domain | Designed behavior | Cloud evidence |
| --- | --- | --- |
| Pod/node | Kubernetes replaces executors; idempotent retry handles ambiguous responses | Phase 18 one-node pod proof only; no GKE/node proof |
| Zone | Regional GKE can place app pods across zones; stateful services each need their own HA | Not tested |
| GKE control plane | Existing pods may continue, but rollout/control actions may stall | Not tested |
| PostgreSQL | Authoritative commands/readiness stop; never write via Redis/Kafka fallback | Local outage evidence only |
| Redis | Queue/projection lag; normal PostgreSQL commands retain truth | Local evidence only |
| Kafka | Outbox persists publication intent; audit/projection lag | Local evidence only |
| Region | This single-region design becomes unavailable; recovery is Phase 21 | Not tested |

## Identity, secrets, state and operations

| Identity | Access boundary |
| --- | --- |
| Terraform executor | Separate human/federated deployment identity; scoped provisioning permissions and GCS state access; never a pod identity. Exact custom role/grants pending real project plan. |
| Future GitHub deploy job | [OIDC to Google Workload Identity Federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines), separate from normal CI and Terraform identity. Release sequencing belongs to Phase 22. |
| GKE node service account | `roles/container.defaultNodeServiceAccount` at project and Artifact Registry Reader on one image repository. Image pulls are node identity, not pod WIF. |
| API/worker Kubernetes service accounts | Secret Accessor only on named database URL/master-key secrets via WIF principal. No owner/editor/infra mutation. |
| Web Kubernetes service account | No GCP API role. |
| Managed Kafka clients | Future narrowly scoped Kafka client identity/ACL; not provisioned yet. |

Autopilot enables [Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity); [Secret Manager's GKE add-on](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component) can mount versions for authorized Kubernetes service accounts. Terraform creates only metadata and bindings. The global Secret Manager resource uses [user-managed replication](https://docs.cloud.google.com/secret-manager/docs/choosing-replication) to keep payload storage in `europe-west4`; strict in-region access/data-residency policy would need a separate regional-service review. A separate secure bootstrap must create secret values, and manifests must mount them so Rails receives `DATABASE_URL` and any key without writing plaintext to Terraform, tfvars, Git or Kubernetes objects in Terraform state. GKE KSA names in manifests must match the Terraform principals. No JSON service-account keys. One project per environment avoids cross-environment IAM/quota/blast-radius overlap and WIF [identity sameness](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) across clusters in a project.

Use one [GCS backend](https://developer.hashicorp.com/terraform/language/backend/gcs) object prefix per environment after a separately bootstrapped bucket, with object versioning, uniform bucket-level access, public access prevention and narrow state IAM. GCS supports locking; bucket existence precedes backend configuration. Bootstrap has its own local state, and no bucket is created by default. State may contain sensitive resource metadata even without payloads, so restrict it. There is no implicit remote state or CI deployment.

Current structured stdout/stderr can map to Cloud Logging; current bounded Prometheus metrics and OTel can map to [Managed Service for Prometheus](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus), Cloud Monitoring and a Collector while retaining Grafana/PromQL. This is an interface choice, not a telemetry migration. Exclude raw keys, private maxima, passwords and payloads; measure log/metric volume and choose retention and exclusions before enabling cloud collection. [Observability pricing](https://cloud.google.com/products/observability/pricing) is usage-dependent. Artifact Registry is regional and stores both app images; cleanup policy, scanning and immutable digest rollout remain deployment work. [Artifact Registry](https://docs.cloud.google.com/artifact-registry/docs/overview) charges for storage/egress and optional scanning.
