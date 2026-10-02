# Phase 19 ExecPlan — Terraform and GCP architecture

Status: Active. Session 1 milestone complete 2026-10-03; checkpoint required. No cloud spend authorized.
Current milestone: Safe non-applied foundation, architecture and cost model documented; next session owns integration gaps.

## Completed

- Confirmed clean Phase 18 handoff commit `d4307f10ff8e9b8be0196b648da38925939548b9`; reviewed phase scope, invariants, Phase 18 final, ADR-014 and relevant implementation.
- Compared GKE/Kafka options, chose `europe-west4`, and recorded [ADR-015](../adr/015-gcp-reference-infrastructure.md), [architecture](../cloud/architecture.md), [cost estimate](../cloud/cost-estimate.md) and [Session 1 research](../cloud/session-1.md).
- Added `infra/terraform/` with disabled state-bucket bootstrap and disabled reference environment: APIs, VPC, private GKE, NAT/PSA, Artifact Registry, Cloud SQL, separately gated Redis, Secret Manager metadata and WIF IAM. No broker, edge, secret version or application workload is provisioned.
- Mapped Kafka auth/TLS, Redis TLS/auth, database credential/TLS, secret mount, Gateway and cloud workload gaps without altering application contracts.
- Adversarial review fixed Secret Manager's initial global automatic-replication choice to a user-managed `europe-west4` storage replica; gated unresolved client/edge security paths remain in the Session 1 report.

## Decisions

| Topic | State | Reason / record |
| --- | --- | --- |
| GCP/Kubernetes and Terraform | ADOPT | Public Catawiki material confirms GCP/Kubernetes and treats Terraform as relevant IaC; no internal architecture claim. ADR-015. |
| Region/projects | ADOPT | `europe-west4`, one project/environment for IAM/quota/WIF isolation; no Catawiki region claim. |
| GKE | ADOPT | Autopilot for managed nodes; Standard deferred until measured cost/control need. |
| PostgreSQL | ADOPT | Cloud SQL 18 Enterprise, private IP/TLS, zonal baseline, regional HA option; PostgreSQL remains sole authority. |
| Redis | DEFER runtime | Private TLS resource defined but disabled pending client/auth work; Basic and Standard HA costed. |
| Kafka | NEEDS EVIDENCE | Managed target preserves protocol, but current rdkafka lacks required auth/TLS and region quote; Pub/Sub substitution rejected. |
| Edge/TLS/DNS | DEFER | Gateway/ALB target; domain, certificate, routes and WSS timeout need later cloud work. |
| IAM/secrets/state | ADOPT foundation | Node pull identity, WIF secret readers, no JSON keys/payloads, disabled GCS bucket bootstrap. |
| Observability | DEFER migration | Cloud Logging/Monitoring/managed Prometheus mapped; nothing enabled. |
| Paid apply | REJECT for current authorization | No GCP authentication, API mutation, billing change or resources. |

## Remaining

1. Session 2: managed Kafka client auth/TLS and provider/ACL design; Redis TLS/auth; Cloud SQL verified TLS and database user bootstrap; Secret Manager version/mount flow and workload KSAs. Preserve local contracts with meaningful tests.
2. Session 2: GKE workload overlay and Gateway/HTTPRoutes/TLS/DNS plan; Terraform edge/private networking refinement and cloud-specific security review.
3. Get a dated `europe-west4` SKU/calculator estimate and official-provider validation/read-only plan in an accessible authorized environment. No apply without separate spending authorization.
4. Final session: static CI, relevant regression/local setup, adversarial review, docs reconciliation and phase completion. Phase 20 stays gated.

## Known failures/limitations

- HashiCorp registry/release endpoints returned a geographic block. Final HCL passed mirrored Google-provider 8.5.0 schema validation; committed locks contain official HashiCorp ZIP hashes. Official-provider validation, authenticated plan, regional quote, cloud connectivity and failure tests remain unverified.
- Current Redis/Kafka clients, secret flow, Cloud SQL user/TLS and cloud ingress prevent a safe full deployment. `enable_redis=false` separately gates provisional Redis. Phase 18 local requests are not production sizes.

## Relevant files

- [Session 1](../cloud/session-1.md), [architecture](../cloud/architecture.md), [cost estimate](../cloud/cost-estimate.md), [Terraform README](../../infra/terraform/README.md), `infra/terraform/`, Phase 18 final and `k8s/base/`.

## Relevant ADRs

- [ADR-015](../adr/015-gcp-reference-infrastructure.md), [ADR-014](../adr/014-local-kubernetes-process-orchestration.md).

## Evidence Index

| Check | Command / method | Result | Evidence |
| --- | --- | --- | --- |
| Phase 18 starting point | `git rev-parse HEAD`, status | Expected commit, clean tree | `d4307f10ff8e9b8be0196b648da38925939548b9` |
| Tool inventory | `command -v`, versions | Host Terraform/gcloud absent; kubectl v1.35.9 | [Session 1](../cloud/session-1.md) |
| Terraform CLI and provider | Docker Terraform 1.16.5; checksum-verified OpenTofu mirror Google provider 8.5.0 | CLI worked; official distribution geoblocked | [Session 1 limits](../cloud/session-1.md) |
| Format | `terraform fmt -check -recursive` | Passed | `infra/terraform/` |
| Static validation | `terraform init -backend=false -input=false`, `terraform validate` in temporary mirror-lock copies of both roots | Both passed on final Session 1 HCL, no credentials | [Session 1 verification](../cloud/session-1.md) |
| Credential-free plan attempt | `terraform plan -refresh=false -var=project_id=placeholder-project` in both roots | Stopped for missing ADC; no GCP mutation | [Session 1 verification](../cloud/session-1.md) |
| Credential scan | `rg` IaC assignments and prose review | No secret value/version in IaC; only boundary prose matches | Session 1 review |
| Docs/lock integrity | Relative-link check of 7 Markdown files; official GitHub SHA256SUMS vs both locks | No missing links; 11 official ZIP hashes match in each lock | Session 1 shell output |
| Cloud spend | Command/action audit | Zero GCP authentication, API changes, resources and billing actions | [Session 1](../cloud/session-1.md) |

## Next-session starting point

Read this plan and `docs/handoffs/latest.md`, then inspect only the client/secret integration paths and Terraform gaps in Remaining item 1. Keep cloud creation gated. Do not restart research or enter Phase 20.
