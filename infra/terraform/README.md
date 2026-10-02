# Phase 19 Terraform foundation

This tree is **non-applied reference infrastructure**. No Google Cloud spend is authorized by Phase 19. The default configuration creates no resources or API changes. Do not run `terraform apply`, create a state bucket, authenticate to a project, or enable the cost gate without separate user authorization.

## Layout and ownership

- `bootstrap/`: a disabled, separately bootstrapped GCS state bucket with versioning, uniform bucket access, public access prevention and destruction protection. It starts with local state because the remote bucket cannot store state before it exists.
- `environments/reference/`: one reference root in `europe-west4`, with `enable_reference_infrastructure=false` by default. Project ID is required as an input, but static `init`/`validate` do not authenticate or mutate GCP.
- `modules/reference/`: VPC/private networking, Autopilot GKE, Artifact Registry, private Cloud SQL, an independently disabled private Redis definition, Secret Manager metadata and narrow workload identity grants. It has no managed Kafka cluster, DNS, certificate, load balancer, Kubernetes workload or secret value.

Terraform describes cloud resources. Kubernetes manifests continue to own application Deployments/Services; GKE Gateway/HTTPRoutes and cloud-specific workload overlays remain later Phase 19 work. [Architecture](../../docs/cloud/architecture.md) and [ADR-015](../../docs/adr/015-gcp-reference-infrastructure.md) identify all deployment blockers.

## Safe static checks

Run from `infra/terraform` with Terraform **1.16.5**:

```sh
terraform fmt -check -recursive
cd environments/reference
terraform init -backend=false -input=false
terraform validate
```

Repeat `init -backend=false` and `validate` under `bootstrap/`. The Google provider is pinned to **8.5.0**, with official ZIP hashes in each root's lock file. Normal `terraform init` can fetch the official provider where HashiCorp endpoints are accessible. In the author's environment those endpoints returned a geographic block; Session 1 used a checksum-verified OpenTofu provider mirror solely for schema validation, then restored the lock files to **official HashiCorp** hashes. No provider-backed plan with GCP credentials was run.

`terraform.tfvars.example` shows placeholder inputs. A default `terraform plan` may require Application Default Credentials merely to configure the Google provider even with zero resources, so it is not part of the no-credential static gate. No credential setup is required for normal repository CI. The example project ID is not a real project.

## Before a future approved deployment

1. Price `europe-west4` and review the explicit cost gate, region, project, operator CIDR and project APIs. Prefer a dedicated project per environment. The execution identity is separate from every runtime Kubernetes service account.
2. Bootstrap a GCS bucket only under separate spending authorization. Secure its local bootstrap state; migrate the reference root to an existing GCS backend with a per-environment prefix and locking. Restrict state IAM. Do not store secret payloads in Terraform.
3. Finish the Kafka TLS/auth client path and broker choice, Redis TLS/auth client path, database user and verified TLS connection, Secret Manager version/bootstrap/mount flow, Gateway/TLS/DNS, image digests, workload identities/manifests, operational checks and cost controls. Validate a real plan before any apply.
4. Treat Cloud SQL `deletion_protection` and `settings.deletion_protection_enabled` as intentional safety controls. Disabling them is a separate reviewed operation. Backups/PITR require later restore testing.

The current reference can provision resources if explicitly enabled, but it cannot yet run the complete application safely. Do not infer availability, cost or connectivity from static validation.
