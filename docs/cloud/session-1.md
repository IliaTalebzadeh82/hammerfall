# Phase 19 Session 1 — GCP research and safe Terraform foundation

Research/access date: 2026-10-03. Starting commit: `d4307f10ff8e9b8be0196b648da38925939548b9`. Status: Session 1 architecture/foundation complete; Phase 19 remains active. No cloud account login, billing attachment, GCP API mutation or paid resource creation occurred.

## Evidence classes

| Class | Finding | Source |
| --- | --- | --- |
| Catawiki publicly confirmed | Catawiki says its platform uses GCP and Kubernetes. Current platform hiring names Terraform or Ansible as relevant IaC. This does **not** establish its GKE mode, region, services or universal IaC choice. | [Engineering](https://catawiki.careers/engineering), [Platform role](https://catawiki.careers/vacancies/platform-engineer-portugal-3270914-8219279) |
| Hammerfall architecture decision | Terraform, `europe-west4`, Autopilot, private Cloud SQL/Redis, managed Kafka target, GKE Gateway target, per-environment project, WIF and GCS state design. | [ADR-015](../adr/015-gcp-reference-infrastructure.md), [architecture](architecture.md) |
| Inference / alternative | European reference region is plausible for this showcase, not a claim about Catawiki location. Standard GKE, third-party managed Kafka and Pub/Sub migration remain alternatives subject to measured requirements. | [Architecture comparison](architecture.md), [cost model](cost-estimate.md) |

## Official product/provider sources and facts used

All links were accessed 2026-10-03; consult live pages again before any approved cloud plan or spend.

| Source | Fact used |
| --- | --- |
| [GKE mode overview](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode), [pricing](https://cloud.google.com/kubernetes-engine/pricing), [Autopilot requests](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests) | Autopilot manages nodes and bills general pods by effective requests; Standard bills nodes; both have a management fee; low requests can be raised. |
| [GKE network isolation](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/network-isolation), [Gateway API](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/gateway-api), [external ALB](https://docs.cloud.google.com/load-balancing/docs/https) | Private nodes need controlled egress; Gateway reconciles load-balancer resources; ALB supports WebSockets. |
| [Cloud SQL versions](https://docs.cloud.google.com/sql/docs/postgres/db-versions), [HA](https://docs.cloud.google.com/sql/docs/postgres/high-availability), [private connectivity](https://docs.cloud.google.com/sql/docs/postgres/connection-options), [pricing](https://cloud.google.com/sql/pricing) | PostgreSQL 18 exists, regional HA is service-specific, private IP is recommended, compute/storage/backups have separate costs. |
| [Redis tiers](https://docs.cloud.google.com/memorystore/docs/redis/memorystore-for-redis-overview), [TLS](https://docs.cloud.google.com/memorystore/docs/redis/about-in-transit-encryption), [pricing](https://cloud.google.com/memorystore/docs/redis/pricing) | Basic is standalone, Standard HA fails over; TLS needs client setup; provisioned GiB is billed continuously. |
| [Managed Kafka overview](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/overview), [creation](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/create-cluster), [locations](https://docs.cloud.google.com/managed-service-for-apache-kafka/docs/locations), [pricing](https://cloud.google.com/managed-service-for-apache-kafka/pricing) | Minimum 3 vCPU, private VPC endpoints, mandatory SASL/IAM or mTLS, TLS, European availability, material fixed and traffic charges. |
| [Artifact Registry](https://docs.cloud.google.com/artifact-registry/docs/overview), [IAM](https://docs.cloud.google.com/artifact-registry/docs/access-control), [pricing](https://cloud.google.com/artifact-registry/pricing) | Regional Docker repository, node image-pull identity and storage/scanning/transfer charges. |
| [GKE WIF](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity), [Secret Manager GKE add-on](https://docs.cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component), [secret IAM](https://docs.cloud.google.com/secret-manager/docs/manage-access-to-secrets), [replication](https://docs.cloud.google.com/secret-manager/docs/choosing-replication) | Kubernetes service-account principals can receive per-secret access without static keys; user-managed replication bounds payload storage location; secret versions need a separate secure bootstrap. |
| [Deployment pipeline federation](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines), [GitHub OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-google-cloud-platform) | A future deploy workflow can exchange GitHub OIDC for short-lived Google credentials; normal CI stays credential-free. |
| [GCS backend](https://developer.hashicorp.com/terraform/language/backend/gcs), [public access prevention](https://docs.cloud.google.com/storage/docs/public-access-prevention), [uniform access](https://docs.cloud.google.com/storage/docs/uniform-bucket-level-access) | Bucket must pre-exist backend; GCS locking/versioning and bucket hardening are available. |
| [Managed Prometheus](https://docs.cloud.google.com/stackdriver/docs/managed-prometheus), [observability pricing](https://cloud.google.com/products/observability/pricing), [VPC pricing](https://cloud.google.com/vpc/network-pricing) | OTel/Prometheus mapping is feasible; logs, samples, NAT, load balancing and data transfer are billable. |
| [Terraform Google provider registry](https://registry.terraform.io/providers/hashicorp/google/latest/docs), [GCS backend](https://developer.hashicorp.com/terraform/language/backend/gcs) | Schema/lock/provider and state design. Terraform binary 1.16.5 and Google provider 8.5.0 are pinned. |

## Findings and implementation

Phase 18's API/web plus seven background roles map to GKE without making pod identity or placement authoritative. Rails retains PostgreSQL transactions, locks, `clock_timestamp()`, idempotency and outbox; Redis and Kafka remain derived. [Architecture](architecture.md) records network, IAM, public/private, edge, observability, connection and failure boundaries. [Cost estimate](cost-estimate.md) separates provisioned and usage charges, two SQL/Redis tiers, managed Kafka economics, Iowa worked arithmetic and the unquoted Netherlands rates.

The Terraform tree contains a disabled bootstrap state-bucket root and a disabled reference environment. Its module defines APIs, VPC/subnet/secondary ranges/PSA/NAT, Autopilot cluster, image repository/node identity, Cloud SQL PostgreSQL 18, a separately disabled private Redis resource, and Secret Manager metadata/WIF access. Default `enable_reference_infrastructure=false` gives zero planned GCP resources; no Kafka, edge load balancer, DNS, certificate, secret value or Kubernetes Deployment is provisioned. `enable_redis=false` remains the default even if infrastructure is enabled. The Redis resource definition has TLS enabled but no AUTH because Redis AUTH's generated string would be retained in Terraform state; this is a deployment gap, not a final security posture. See [Terraform README](../../infra/terraform/README.md).

## Verification and limits

- Tool inventory: `terraform` and `gcloud` absent from host PATH; `kubectl` client v1.35.9. The official `hashicorp/terraform:1.16.5` image ran and supplied a local CLI copy for static checks. No gcloud auth or project configuration changed.
- `terraform fmt -check -recursive` passed. Both roots passed `terraform init -backend=false -input=false` and `terraform validate` using a locally installed OpenTofu mirror of Google provider 8.5.0 whose ZIP checksum matched that mirror's published SHA256SUMS. HashiCorp's registry discovery and binary distribution returned a geographic block in this environment. The committed lock files contain **official HashiCorp** release ZIP hashes (from its GitHub release), not the alternate mirror checksum. The final config needs validation against the official provider in an accessible environment; the mirror validates HCL/schema equivalence only to the extent the fork matches. No credentials were used.
- A credential-free `terraform plan -refresh=false` was attempted for both disabled roots; the Google provider still requested Application Default Credentials, so no provider-backed plan was obtained. This is an expected limit, not a GCP account test. No `apply`, GCP create/deploy, billing or live cluster command ran.
- Phase 18 resource requests were used only for explicit cost stress arithmetic. No cloud pod admission, pricing bill, SQL connection limit, zone failure, broker auth or edge/WSS behavior was measured.

## Adversarial review

The review found automatic Secret Manager replication would permit global payload storage despite a European reference region; the Terraform metadata now uses one user-managed `europe-west4` replica. This bounds storage location but does not by itself establish a strict data-residency regime. No application source or authoritative auction protocol changed: PostgreSQL still decides ordering, deadline, idempotency and winner. A regional GKE control plane does not supply Cloud SQL/Redis/Kafka HA, and enabled backups do not prove recovery.

Deployment blockers remain explicit: current Kafka clients cannot authenticate to managed Kafka, Redis TLS/auth is unresolved and separately disabled, Rails lacks the cloud database credential/verified-TLS flow, and the Gateway/TLS/domain and workload overlays are absent. The GKE control endpoint is publicly reachable only from a supplied operator CIDR, rather than fully private. Normal CI has no cloud credential or apply path. Static inspection found no production secret value, broad owner/editor role, public stateful endpoint or accidental default cost flag. These findings require later verification; no real plan, cloud security proof or cost bill was inferred from source review.

## Open decisions for Session 2

1. Implement and test managed Kafka SASL/IAM or mTLS `rdkafka` configuration, topics/ACLs and Terraform broker module only after cost/security review; retain partition, offset and redelivery semantics. A third-party Kafka option needs the same proof.
2. Decide Redis AUTH/TLS client and out-of-state secret flow, or justify a cluster IAM alternative. Current reference cannot safely run existing `redis://` clients.
3. Supply Cloud SQL user/bootstrap and verified Rails TLS connection without a Terraform-state password; wire Secret Manager mounts/KSAs to all roles and db-prepare.
4. Build GKE workload overlay, Gateway/HTTPRoutes, domain/certificate/HTTPS redirect and WSS timeout policy. No domain is owned or changed here.
5. Quote Netherlands SKUs, refine connections, node/pod admission, NAT/edge/log volumes, IAM for Terraform execution and GCS backend migration; review a real plan if separately authorized and read-only.
6. Finish static CI and adversarial security review, then final phase regression. Phase 20 remains gated.
