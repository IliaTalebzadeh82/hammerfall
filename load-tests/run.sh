#!/usr/bin/env bash
set -euo pipefail

# Usage: load-tests/run.sh SCENARIO MANIFEST VUS DURATION RESULT_DIR
scenario=${1:?scenario name required}
manifest=${2:?manifest path required}
vus=${3:?VU count required}
duration=${4:?duration required}
result_dir=${5:?result directory required}
case "$scenario" in warmup|normal-auction|hot-auction|distributed-auction|duplicate-retries|duplicate-burst|classifier-sabotage|final-minute|final-ten|websocket-fanout) ;; *) exit 2 ;; esac
test -f "$manifest"
mkdir -p "$result_dir"
manifest=$(realpath "$manifest")
result_dir=$(realpath "$result_dir")
repo=$(realpath "$(dirname "$0")/..")
case "$manifest" in "$repo"/*) ;; *) echo 'manifest must be inside repository' >&2; exit 2 ;; esac
case "$result_dir" in "$repo"/*) ;; *) echo 'result directory must be inside repository' >&2; exit 2 ;; esac

set +e
docker run --rm --network host --user "$(id -u):$(id -g)" \
  -v "$repo:/work" -w /work \
  -e "MANIFEST=/work/${manifest#"$repo"/}" -e "VUS=$vus" -e "DURATION=$duration" \
  -e "THINK_SECONDS=${THINK_SECONDS:-0.05}" -e "REQUEST_TIMEOUT=${REQUEST_TIMEOUT:-15s}" \
  grafana/k6:1.8.1 run --summary-export "/work/${result_dir#"$repo"/}/summary.json" \
  "load-tests/$scenario.js" > "$result_dir/k6.log" 2>&1
k6_exit=$?
set -e
tail -n 38 "$result_dir/k6.log"
gzip -n "$result_dir/k6.log"
exit "$k6_exit"
