#!/usr/bin/env bash
set -euo pipefail

# Usage: load-tests/benchmark.sh normal|hot|duplicate VUS DURATION [AUCTIONS] [USERS]
kind=${1:?scenario required}
vus=${2:?VUs required}
duration=${3:?duration required}
if [[ ${REQUIRE_OTEL:-true} == true ]] && \
   [[ $(docker compose exec -T api printenv OTEL_ENABLED) != true ]]; then
  echo 'API OTEL_ENABLED must be true for a primary benchmark' >&2
  exit 2
fi
case "$kind" in
  normal) script=normal-auction; auctions=${4:-8}; users=${5:-32} ;;
  hot) script=hot-auction; auctions=1; users=${5:-32} ;;
  duplicate) script=duplicate-retries; auctions=1; users=1 ;;
  *) echo "unknown scenario: $kind" >&2; exit 2 ;;
esac

fixture="load-tests/fixtures/$(date -u +%Y%m%dT%H%M%SZ)-$kind.json"
python3 load-tests/prepare.py --scenario "$kind" --auctions "$auctions" \
  --users "$users" --minutes 20 --output "$fixture"
run_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["run_id"])' "$fixture")
result_dir="docs/benchmarks/$run_id-$kind"
mkdir -p "$result_dir/warmup"
cat > "$result_dir/commands.txt" <<EOF
git SHA: $(git rev-parse HEAD)
fixture: python3 load-tests/prepare.py --scenario $kind --auctions $auctions --users $users --minutes 20 --output <ignored manifest>
warm-up: load-tests/run.sh warmup <ignored manifest> 1 5s $result_dir/warmup
measurement: load-tests/run.sh $script <ignored manifest> $vus $duration $result_dir
checker: docker compose exec -T -e BENCHMARK_MANIFEST=<ignored manifest JSON> api bin/rails runner script/benchmark_verify.rb
telemetry wait: 20 seconds after k6 for exporter/scrape settlement
EOF
load-tests/run.sh warmup "$fixture" 1 5s "$result_dir/warmup" > /dev/null
python3 load-tests/capture.py --manifest "$fixture" --stage before --result-dir "$result_dir"
set +e
(
  sleep "$((${duration%s} / 2))"
  python3 load-tests/capture.py --manifest "$fixture" --stage during --result-dir "$result_dir"
) > "$result_dir/during-capture.log" 2>&1 &
capture_pid=$!
load-tests/run.sh "$script" "$fixture" "$vus" "$duration" "$result_dir"
k6_exit=$?
set -e
wait "$capture_pid"
sleep 20
python3 load-tests/capture.py --manifest "$fixture" --stage after --result-dir "$result_dir"
docker compose exec -T -e "BENCHMARK_MANIFEST=$(cat "$fixture")" api \
  bin/rails runner script/benchmark_verify.rb > "$result_dir/verify.json"
python3 load-tests/report.py "$result_dir"
python3 - "$result_dir/summary.json" <<'PY'
import json,sys
metrics=json.load(open(sys.argv[1]))['metrics']
bad={key:metrics.get('benchmark_'+key,{}).get('count',0) for key in
     ('client_error','server_error','timeout','transport_error')}
if any(bad.values()):
    raise SystemExit(f'unexpected request outcomes: {bad}')
PY
printf 'k6_exit=%s\nresult_dir=%s\n' "$k6_exit" "$result_dir"
exit "$k6_exit"
