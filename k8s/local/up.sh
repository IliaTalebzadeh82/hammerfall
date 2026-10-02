#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# Only the three stateful dependencies and topic initializer run in Compose.
docker compose stop api api-replica-b api-proxy web auction-closer sidekiq \
  outbox-publisher kafka-outbox-publisher kafka-audit-consumer \
  kafka-projection-consumer reconciliation-scheduler
docker compose up -d db redis kafka kafka-init

if ! kind get clusters | rg -qx hammerfall; then
  kind create cluster --name hammerfall --wait 120s
fi

network=$(docker network ls --filter 'label=com.docker.compose.project=hammerfall' --format '{{.Name}}' | rg '^hammerfall_default$')
if ! docker inspect hammerfall-control-plane --format '{{json .NetworkSettings.Networks}}' | rg -q '"hammerfall_default"'; then
  docker network connect "$network" hammerfall-control-plane
fi

k() { kubectl --context kind-hammerfall "$@"; }
k apply -f k8s/base/namespace.yaml

# Do not write the local database password to a generated manifest or log.
docker exec hammerfall-db-1 sh -c 'printf %s "$POSTGRES_PASSWORD"' |
  k -n hammerfall create secret generic hammerfall-local-db \
    --from-file=PGPASSWORD=/dev/stdin \
    --from-literal=PGUSER="$(docker exec hammerfall-db-1 printenv POSTGRES_USER)" \
    --dry-run=client -o yaml |
  k apply -f -

# The addresses are discovered afresh. Kafka advertises kafka:9092; inside
# the namespace that hostname resolves to the selectorless Service below.
for dependency in db redis kafka; do
  container="hammerfall-${dependency}-1"
  address=$(docker inspect "$container" --format '{{(index .NetworkSettings.Networks "hammerfall_default").IPAddress}}')
  case "$dependency" in
    db) port=5432; name=postgres ;;
    redis) port=6379; name=redis ;;
    kafka) port=9092; name=kafka ;;
  esac
  cat <<EOF | k apply -f -
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ${dependency}-compose
  namespace: hammerfall
  labels:
    kubernetes.io/service-name: ${dependency}
    endpointslice.kubernetes.io/managed-by: hammerfall-local-script
addressType: IPv4
ports:
  - name: ${name}
    protocol: TCP
    port: ${port}
endpoints:
  - addresses: ["${address}"]
    conditions:
      ready: true
EOF
done

tag_file="/tmp/hammerfall-phase18-image-tag-${UID}"
if [[ ${1:-} == --no-build ]]; then
  if [[ ! -r "$tag_file" ]]; then
    printf 'No prior local image tag found; run without --no-build first.\n' >&2
    exit 2
  fi
  image_tag=$(cat "$tag_file")
else
  image_tag="phase18-$(date -u +%Y%m%d%H%M%S)-$$"
  docker build -f infrastructure/api-k8s.Dockerfile -t "hammerfall-api:${image_tag}" .
  docker build -f infrastructure/web-k8s.Dockerfile -t "hammerfall-web:${image_tag}" .
  printf '%s\n' "$image_tag" > "$tag_file"
fi
if [[ ! "$image_tag" =~ ^phase18-[0-9]{14}-[0-9]+$ ]]; then
  printf 'Invalid local image tag.\n' >&2
  exit 2
fi
# The upstream multi-platform nginx image is pulled by the node. Docker's
# locally cached manifest can lack non-host digests, which `kind load` rejects.
kind load docker-image --name hammerfall "hammerfall-api:${image_tag}" "hammerfall-web:${image_tag}"

# Render only image references into a temporary directory. Applying the static
# phase18 placeholder tag on an existing Deployment would otherwise trigger a
# stale intermediate rollout before the new image could be selected.
render_dir=$(mktemp -d /tmp/hammerfall-k8s-render.XXXXXX)
trap 'rm -r "$render_dir"' EXIT
mkdir "$render_dir/base"
for manifest in k8s/base/*.yaml; do
  sed -e "s/hammerfall-api:phase18/hammerfall-api:${image_tag}/g" \
      -e "s/hammerfall-web:phase18/hammerfall-web:${image_tag}/g" \
      "$manifest" > "$render_dir/base/$(basename "$manifest")"
done
sed "s/hammerfall-api:phase18/hammerfall-api:${image_tag}/g" \
  k8s/local/db-prepare.yaml > "$render_dir/db-prepare.yaml"
k apply -f k8s/base/config.yaml -f k8s/base/dependencies.yaml
k -n hammerfall delete job db-prepare --ignore-not-found=true --wait=true
k apply -f "$render_dir/db-prepare.yaml"
k -n hammerfall wait --for=condition=complete job/db-prepare --timeout=180s
k apply -f "$render_dir/base/"
k -n hammerfall rollout status deployment/api --timeout=180s
k -n hammerfall rollout status deployment/web --timeout=180s
k -n hammerfall get pods -o wide

printf '\nAccess the web through: kubectl --context kind-hammerfall -n hammerfall port-forward svc/web 8080:8080\n'
