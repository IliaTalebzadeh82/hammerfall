# Phase 19 ExecPlan — Terraform and GCP architecture

Status: **Active; final local/static verification complete 2026-10-03, hosted CI pending.** Phase 20 has not started. No cloud spend or resource mutation authorized.
Current milestone: close hosted CI and phase documentation against the [final report](../cloud/phase-19-final.md).

## Completed

- Session 1: selected the `europe-west4` Autopilot/Cloud SQL/Redis/managed Kafka/Gateway reference, recorded [ADR-015](../adr/015-gcp-reference-infrastructure.md), [architecture](../cloud/architecture.md), [cost model](../cloud/cost-estimate.md), and disabled Terraform foundation. See [Session 1](../cloud/session-1.md).
- Session 2: verified Google's documented non-Java Managed Kafka OAuth helper path for librdkafka and added a centralized Ruby local/GCP client config. Kept existing event, partition, offset, retry and auction authority semantics. Added gated Kafka cluster/topic/ACL/IAM Terraform, with distinct Kafka identities and default-deny ACL sentinel.
- Session 2: centralized Sidekiq/projection Redis config. Classic Memorystore uses private verified TLS but deliberately no AUTH because its generated AUTH string would enter Terraform state. `enable_redis=false` remains the default.
- Session 2: added mounted Rails secret files and Cloud SQL verified-TLS boot guard; modeled shared CA, automatic rotation, private PSA DNS and four Secret Manager metadata containers. Production dummy boot discovered `SECRET_KEY_BASE` is required and then passed after correction. SQL user/password/secret versions remain separate bootstrap work.
- Session 2: added static GKE overlay with seven KSAs, read-only Secret Manager CSI, Kafka OAuth helper sidecars, direct web Service/Gateway routing, HTTPS redirect, API `/ready` health, suspended `db-prepare` and immutable digest render contract. Local base remains intact except a Kustomization file. Added [Session 2 report](../cloud/session-2.md), [overlay README](../../k8s/overlays/gcp/README.md) and updated architecture/cost/ADR/Terraform README.

## Decisions

| Topic | Current decision | Evidence / limit |
| --- | --- | --- |
| Managed Kafka | Separate disabled gate; Ruby/librdkafka OIDC via Google's loopback ADC helper, linked GSA identities and narrow ACLs | Official Google auth/ACL docs and [Session 2](../cloud/session-2.md); live token/ACL proof pending. |
| Redis | Classic Memorystore private TLS without AUTH, gated off | Cluster topology conflicts with Sidekiq; classic AUTH in Terraform state violates secret boundary. Requires deployment security review. |
| Cloud SQL | Direct libpq, private PSA DNS and `verify-full` with shared CA | No proxy/IAM DB login overhead; actual cert/DNS/live connection pending. |
| Secrets | Metadata/IAM in Terraform, values/versions through separate secure bootstrap, CSI read-only mounts | No value/version in IaC. Version `1` manifest references need bootstrap and rotation procedure. |
| Edge | Global GKE Gateway with Certificate Manager map; HTTP redirect, same-origin WSS/API | Static only; domain, certificate, IP, live admission/traffic pending. |
| Cost | Managed Kafka remains separately material; Iowa arithmetic only | Public `europe-west4` SKU quote unavailable. |

## Verified

Session 3 final regression: 461 RSpec examples, 0 failures, 3 expected broker-gated pendings, seed 45789; Ruby lint/security/Zeitwerk/syntax passed; 74 Vitest tests and frontend lint/format/types/build passed. Compose rebuilt healthy and proved Kafka outbox/audit, Redis projection, Sidekiq enqueue and auction lifecycle. The initial kind base apply exposed the new Kustomization file being applied directly; `up.sh` was fixed, and a rerun proved two API/two web/seven background roles, lifecycle smoke and API replacement. Base render: 17 resources; cloud overlay: 29. Terraform 1.16.5 format, three official-archive provider validations, four root and three module mock tests passed. The official release ZIP was checked against the lock-file hash; registry discovery remained unavailable. No GCP credential, plan or apply. See [final report](../cloud/phase-19-final.md).

| Check | Command / method | Result | Evidence / limit |
| --- | --- | --- | --- |
| Focused Compose integration | `docker compose exec -T -e RAILS_ENV=test api bundle exec rspec` with Kafka/Redis/secret config, Kafka outbox and Redis projection specs | **41 examples, 0 failures, 1 pre-existing live-broker pending**, seed 46442 | Local PostgreSQL, Redis, Kafka; no managed service. |
| Ruby lint | `bundle exec rubocop` on 12 changed Ruby/spec files | **12 files, 0 offenses** | Focused scope. |
| Production boot | Dummy `SECRET_KEY_BASE_FILE`, production `rails runner` | `production_booted` | Dummy DB URL; no SQL connection. Initial attempt failed without key, then fixed. |
| Terraform format/schema | Terraform 1.16.5 `fmt -check -recursive`; `validate` reference/module/bootstrap in temporary mirror copies | **Passed** | Google provider 8.5.0 checksum-verified OpenTofu mirror; official distribution geoblocked, no ADC. |
| Terraform mock plans | `terraform test` in reference root and module | **4 + 2 passed, 0 failed** | Proves default/gated graph shapes, not a provider-backed plan or apply. |
| Kubernetes static | `kubectl kustomize` base and overlay; `ruby k8s/overlays/gcp/validate.rb`; dummy `render.py` | **28 cloud resources; identity/mount/route/health checked; no placeholders** | No GKE CRD admission or live networking. |
| No-cloud boundary | Command/action review | **No auth, API changes, resources, apply, secrets or charges created** | User cost boundary retained. |

## Remaining

1. Commit/push final code and documentation; inspect hosted API, web and Compose CI; record the workflow evidence, then mark Phase 19 complete and rewrite the Phase 20 handoff.
2. For any future authorized deployment: obtain a dated Netherlands quote and real plan; securely bootstrap SQL app role/password, key/CA secret versions; provide domain, cert map, static IP, images; prove GKE WIF/CSI, SQL TLS/DNS, Redis/Kafka connectivity/ACLs and Gateway/WSS. Redis no-AUTH requires a specific security decision before enabling it. Live paid proof is not required to complete Phase 19 under the phase spec, but must remain labeled unverified.

## Known failures/limitations

- HashiCorp registry/distribution geo-blocked official provider validation. Mirror 8.5.0 passed schema/mock checks; no ADC or real plan. Cloud SQL provider-computed DNS names and Kafka ACL acceptance remain live-plan/provisioning risks.
- Classic Redis has no application AUTH in the static reference; do not describe it as production secure. Broker and Redis are separately gated off by default. Secret Manager metadata has no payload/version; overlay points to version `1` only as a bootstrap contract.
- Autopilot pod admission/effective resources, GKE Gateway/CSI/WIF, Cloud SQL TLS chain, Managed Kafka OAuth/ACLs, private networking, public WSS, failure recovery and cost remain unverified live. A local kind cluster was unavailable in Session 2; the full local regression is Session 3 work.

## Relevant files and ADRs

- [Session 2](../cloud/session-2.md), [architecture](../cloud/architecture.md), [cost estimate](../cloud/cost-estimate.md), [Terraform README](../../infra/terraform/README.md), [GKE overlay README](../../k8s/overlays/gcp/README.md), `apps/api/app/services/{kafka_client_config,redis_connection_config}.rb`, `apps/api/lib/secret_files.rb`, `infra/terraform/`, `k8s/overlays/gcp/`.
- [ADR-015](../adr/015-gcp-reference-infrastructure.md), [ADR-014](../adr/014-local-kubernetes-process-orchestration.md).

## Next-session starting point

Start a fresh Codex conversation. Read `AGENTS.md`, [latest handoff](../handoffs/latest.md), this plan, [Phase 19 spec](../phases/phase-19.md), and [Session 2](../cloud/session-2.md); use [context map](../context-map.md) for targeted implementation. Begin with the final regression and static/adversarial gates, then close documentation and phase only on actual evidence. Do not enter Phase 20 or create GCP resources without a separate explicit request.
