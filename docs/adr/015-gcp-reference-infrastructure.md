# ADR-015: GCP reference infrastructure and explicit deployment boundary

Status: Accepted for Phase 19 architecture, 2026-10-03. No cloud deployment approved.

## Context

Phase 18 proved local one-node process orchestration with PostgreSQL, Redis and Kafka in Compose. It did not prove managed service connectivity, multi-zone availability, TLS, cloud ingress or production capacity. Public [Catawiki engineering material](https://catawiki.careers/engineering) confirms GCP and Kubernetes. A [current platform vacancy](https://catawiki.careers/vacancies/platform-engineer-portugal-3270914-8219279) treats Terraform or Ansible as relevant IaC experience. Neither source reveals Catawiki's GKE mode, database, broker, region or Terraform estate.

## Decision

Use a single dedicated GCP project for each future environment and a European `europe-west4` reference region. Describe cloud resources with Terraform and keep application Deployments, Services, Gateway and routes in Kubernetes manifests. Use GKE Autopilot for the reference application processes, Cloud SQL for PostgreSQL as the sole auction authority, private Memorystore for Redis as derived queue/projection infrastructure, Artifact Registry for API/web images, Secret Manager metadata plus Workload Identity Federation for GKE, and a private VPC with private nodes and controlled outbound NAT. A separate deployment identity must provision infrastructure; runtime pods receive no infrastructure mutation rights. No service-account JSON keys.

Retain Kafka semantics. Google Managed Service for Apache Kafka is the preferred faithful managed target, but its authenticated TLS client integration and cost remain an explicit deployment gate. Terraform does not create a broker by default or substitute Pub/Sub. The edge target is GKE Gateway backed by an external Application Load Balancer with TLS at the edge; DNS, certificate, static IP and Gateway manifests await a domain and separate work.

Cloud SQL private IP and TLS are selected. The Terraform reference creates Secret Manager metadata and IAM grants, never payload versions. Redis remains a derived service behind its own cost gate.

**Session 2 refinement (2026-10-03):** Direct Cloud SQL uses a shared Google-managed CA, private `sql-psa.goog` DNS and libpq `sslmode=verify-full`; Terraform models the private DNS record, while a separate bootstrap supplies the SQL user/password and trusted CA bundle. Rails production needs `SECRET_KEY_BASE`, not just `RAILS_MASTER_KEY`, because this repository has no encrypted credentials file. Mounted files supply the database URL and key. The GKE overlay uses Gateway and removes local Nginx.

Managed Kafka remains a separate disabled cost gate. Google's non-Java OAUTHBEARER helper runs on pod loopback beside Ruby/librdkafka. Three linked GKE-to-IAM service accounts provide distinct Kafka ACL email principals without static keys. Kafka IAM grants only connect; topic/group/cluster ACLs authorize operations. This is statically modeled, not live authenticated.

Classic Memorystore Redis remains disabled by default. It uses private VPC and verified TLS **without Redis AUTH** in this reference because the provider's computed AUTH string enters Terraform state, while Redis Cluster IAM is not a Sidekiq-compatible topology. This is an explicit security limitation that must be reviewed before any Redis deployment. The application supports a mounted AUTH password for a future non-Terraform credential path, but this reference does not claim one.

The default Terraform configuration creates no resources, and all billable reference infrastructure requires `enable_reference_infrastructure=true` plus a project and an operator CIDR. The GCS state bucket has a separate, disabled bootstrap root. `terraform apply` and other GCP mutations require separate spending authorization.

## Alternatives considered

- **GKE Standard:** more node and placement control; charges for whole nodes and increases node sizing, patching and autoscaling duties. No current workload requires that control. Revisit if sustained requests, special node features or measured cost favor it.
- **Self-managed Kafka in GKE or VMs:** may reduce a small bill but adds broker storage, replication, upgrade and recovery obligations that a one-person reference cannot claim to operate safely.
- **Pub/Sub:** usage pricing could suit a small portfolio but changes partitions, consumer groups, offset commits and redelivery behavior. This needs a separately tested application architecture migration.
- **Public Cloud SQL/Redis/broker endpoints:** unnecessary public attack surface. Private service connectivity is the reference boundary.
- **Terraform-managed Kubernetes Deployments:** couples cloud lifecycle/state to each application rollout; Kubernetes manifests already own that layer.

## Consequences and risks

Autopilot can increase Phase 18's low pod requests to enforced minima, so the local requests cannot be billed as production sizing. Scaling pods multiplies PostgreSQL connection pools and hot-row pressure. A regional GKE cluster alone does not make Cloud SQL, Redis or Kafka highly available. PostgreSQL outage stops authoritative writes; Redis/Kafka loss leaves auction truth in PostgreSQL but delivery/read projections can lag. Backup/PITR settings do not establish RPO, RTO or tested recovery; Phase 21 owns those.

The Session 1 Terraform was a safe foundation. Session 2 added the static edge, broker client adapter, secret mounts, verified-TLS client guard and workload overlay. A real domain, certificate map/IP, immutable image digests, secret versions, database user, Redis security decision, provider-backed plan and live failure proof remain outstanding. See [architecture](../cloud/architecture.md), [cost model](../cloud/cost-estimate.md), and the [ExecPlan](../plans/phase-19-execplan.md).

## Revisit when

Measured load and connection usage exist; a domain and deployment are authorized; managed Kafka client integration is tested; a cheaper semantic-equivalent broker is proven; or cost/availability goals require Standard, regional Cloud SQL, Redis HA or another region.
