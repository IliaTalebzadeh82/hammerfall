# GKE reference overlay (static)

This overlay describes the Phase 19 cloud workload contract; it has not been applied to GKE. `kubectl kustomize k8s/overlays/gcp` renders placeholders for a single `reference` environment in `europe-west4`. `ruby k8s/overlays/gcp/validate.rb` checks the rendered KSA, secret, workload, route and health boundaries without a cluster. `kubectl kustomize k8s/base` remains the local Phase 18 base.

The overlay removes Compose/kind DB, Redis and Kafka selectorless Services, the web Nginx sidecar and its ConfigMap, and the local DB Secret reference. The Gateway serves the web directly, routes `/api` and `/cable` to Rails, redirects HTTP to HTTPS, and checks API `/ready`. The web stays on the same public origin. Nine Deployments use explicit service accounts; Rails containers read database URL, secret key base and CA files from read-only GKE Secret Manager CSI mounts. Kafka roles additionally run Google's ADC-backed local OAuth helper on pod loopback. `db-prepare` is suspended pending credential and migration bootstrap.

`render.py` requires project ID, public hostname, certificate map name, global static IP name, private Redis host, complete managed Kafka bootstrap `host:port`, and three immutable Artifact Registry SHA-256 digests. Example syntax with deliberately nondeployable values:

```sh
python3 k8s/overlays/gcp/render.py \
  --project-id hammerfall-example-project \
  --hostname example.org \
  --certificate-map example-cert-map \
  --static-ip-name example-global-ip \
  --redis-host redis.internal.example \
  --kafka-bootstrap-address broker.internal.example:9092 \
  --api-digest "$(printf 'a%.0s' {1..64})" \
  --web-digest "$(printf 'b%.0s' {1..64})" \
  --kafka-auth-digest "$(printf 'c%.0s' {1..64})" \
  --output /tmp/hammerfall-gcp-example.yaml
```

The renderer only writes YAML. Its syntax check does not prove that a domain, certificate, address, images, DNS, WIF, CSI or service exists. All four Secret Manager containers need version `1` before any affected pod can start; secret rotation requires an intentional version reference update and rollout. The Kafka helper image must be built and reviewed from `kafka-auth/` before its digest is supplied. Keep the default Terraform gates off until a separately authorized deployment and cost review.

## Separate secure bootstrap for a future authorized deployment

Terraform would create Cloud SQL instance/database, the private PSA DNS record, and Secret Manager containers/IAM. A separate restricted operator or bootstrap process must set the initial `postgres` password (Google supports `gcloud sql users set-password postgres --prompt-for-password`), create an application login, grant only the privileges needed for the Rails database and migrations, and verify connectivity from the private VPC. [Cloud SQL user guidance](https://docs.cloud.google.com/sql/docs/postgres/create-manage-users) warns that a built-in user created without custom database roles gets `cloudsqlsuperuser`; avoid leaving that grant on the app role. Do not pass the app password as a CLI argument, put it in Terraform, shell history or a tracked file. An approved, restricted console or bootstrap program can handle the password and write the URL version to Secret Manager outside Terraform.

Download the shared regional [Cloud SQL CA bundle](https://docs.cloud.google.com/sql/docs/postgres/authorize-ssl) and the instance's [Memorystore CA](https://docs.cloud.google.com/memorystore/docs/redis/about-in-transit-encryption) through the approved operator path. Store each bundle and a freshly generated Rails `SECRET_KEY_BASE` as separate Secret Manager versions. The URL must use the private `*.sql-psa.goog` DNS name, application user, encoded password, `sslmode=verify-full`, and `sslrootcert=/var/run/hammerfall-secrets/cloud-sql-ca.pem`. Verify DNS resolves to the private IP and libpq verifies the server chain before unsuspending `db-prepare`. `db-prepare` must complete before rolling API and workers. No bootstrap, version creation or migration ran in Session 2.

The classic Memorystore reference intentionally uses private TLS without Redis AUTH because the provider's computed AUTH string would enter Terraform state. This is a security limitation, and `enable_redis=false` remains the default. Kafka and Redis are independently gated. Actual CSI mount, WIF token exchange, Kafka ACL enforcement, Cloud SQL certificate validation, Gateway provisioning, WebSocket upgrade and GKE admission remain live proof.
