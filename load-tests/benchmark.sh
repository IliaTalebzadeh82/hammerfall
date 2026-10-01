#!/usr/bin/env bash
set -euo pipefail

# Usage: load-tests/benchmark.sh normal|hot|distributed|duplicate|burst|closing|challenge|fanout VUS DURATION [AUCTIONS] [USERS]
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
  distributed) script=distributed-auction; auctions=${4:-8}; users=${5:-64} ;;
  duplicate) script=duplicate-retries; auctions=1; users=1 ;;
  burst) script=duplicate-burst; auctions=1; users=1 ;;
  closing) script=final-minute; auctions=1; users=${5:-64} ;;
  challenge) script=final-ten; auctions=1; users=$vus ;;
  fanout) script=websocket-fanout; auctions=1; users=${5:-24} ;;
  *) echo "unknown scenario: $kind" >&2; exit 2 ;;
esac

fixture="load-tests/fixtures/$(date -u +%Y%m%dT%H%M%SZ)-$kind.json"
prepare_extra=()
if [[ $kind == closing ]]; then prepare_extra=(--seconds 20); fi
if [[ $kind == challenge ]]; then prepare_extra=(--seconds 40); fi
prepare_extra_text="${prepare_extra[*]}"
python3 load-tests/prepare.py --scenario "$kind" --auctions "$auctions" \
  --users "$users" --minutes 20 "${prepare_extra[@]}" --output "$fixture"
run_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["run_id"])' "$fixture")
result_dir="docs/benchmarks/$run_id-$kind"
mkdir -p "$result_dir/warmup"
cat > "$result_dir/commands.txt" <<EOF
git SHA: $(git rev-parse HEAD)
fixture: python3 load-tests/prepare.py --scenario $kind --auctions $auctions --users $users --minutes 20 $prepare_extra_text --output <ignored manifest>
warm-up: load-tests/run.sh warmup <ignored manifest> 1 5s $result_dir/warmup
measurement: load-tests/run.sh $script <ignored manifest> $vus $duration $result_dir
checker: docker compose exec -T -e BENCHMARK_MANIFEST=<ignored manifest JSON> api bin/rails runner script/benchmark_verify.rb
telemetry wait: 20 seconds after k6 for exporter/scrape settlement
EOF
if [[ $kind == challenge ]]; then
  printf 'during capture: targeted approximately five seconds before original deadline, after requests begin\n' >> "$result_dir/commands.txt"
fi
if [[ $kind == closing || $kind == challenge ]]; then
  printf 'closer observation: python3 load-tests/wait_closed.py <ignored manifest> %s/closer-observations.json --timeout 240\n' "$result_dir" >> "$result_dir/commands.txt"
fi
if [[ ${PROFILE_RUNTIME:-false} == true ]]; then
  printf 'runtime sampling: docker compose exec -T api ruby script/performance_sample.rb %s 0.2 > %s/runtime.jsonl\n' "$((${duration%s} + 2))" "$result_dir" >> "$result_dir/commands.txt"
fi
if [[ ${PROFILE_CPU:-false} == true ]]; then
  printf 'CPU profiling: trigger StackProf CPU samples for %s seconds; copy dump and GC counters after load\n' "${duration%s}" >> "$result_dir/commands.txt"
fi
load-tests/run.sh warmup "$fixture" 1 5s "$result_dir/warmup" > /dev/null
python3 load-tests/capture.py --manifest "$fixture" --stage before --result-dir "$result_dir"
set +e
(
  if [[ $kind == challenge ]]; then
    delay=$(python3 - "$fixture" <<'PY'
import datetime as dt,json,sys
fixture=json.load(open(sys.argv[1]))
deadline=dt.datetime.fromisoformat(fixture['ends_at'].replace('Z','+00:00'))
print(max(0,(deadline-dt.datetime.now(dt.timezone.utc)).total_seconds()-5))
PY
)
  else
    delay="$((${duration%s} / 2))"
  fi
  sleep "$delay"
  python3 load-tests/capture.py --manifest "$fixture" --stage during --result-dir "$result_dir"
) > "$result_dir/during-capture.log" 2>&1 &
capture_pid=$!
profile_pid=
if [[ ${PROFILE_CPU:-false} == true ]]; then
  docker compose exec -T api ruby -e 'File.write("/tmp/hammerfall-puma-control/profile.start", "#{ARGV[0]} #{ARGV[1]}")' "$run_id" "${duration%s}"
fi
if [[ ${PROFILE_RUNTIME:-false} == true ]]; then
  docker compose exec -T api ruby script/performance_sample.rb "$((${duration%s} + 2))" 0.2 > "$result_dir/runtime.jsonl" &
  profile_pid=$!
fi
load-tests/run.sh "$script" "$fixture" "$vus" "$duration" "$result_dir"
k6_exit=$?
set -e
wait "$capture_pid"
profile_exit=0
if [[ -n $profile_pid ]]; then wait "$profile_pid" || profile_exit=$?; fi
cpu_profile_exit=0
if [[ ${PROFILE_CPU:-false} == true ]]; then
  docker compose cp "api:/app/tmp/$run_id.stackprof.dump" "$result_dir/cpu.stackprof.dump" > /dev/null || cpu_profile_exit=$?
  docker compose cp "api:/app/tmp/$run_id.gc.json" "$result_dir/gc.json" > /dev/null || cpu_profile_exit=$?
fi
closer_exit=0
if [[ $kind == closing || $kind == challenge ]]; then
  python3 load-tests/wait_closed.py "$fixture" "$result_dir/closer-observations.json" --timeout 240 || closer_exit=$?
fi
sleep 20
python3 load-tests/capture.py --manifest "$fixture" --stage after --result-dir "$result_dir"
set +e
docker compose exec -T -e "BENCHMARK_MANIFEST=$(cat "$fixture")" api \
  bin/rails runner script/benchmark_verify.rb > "$result_dir/verify.json"
verify_exit=$?
set -e
python3 load-tests/report.py "$result_dir"
python3 - "$result_dir/summary.json" "$kind" "$vus" <<'PY'
import json,sys
metrics=json.load(open(sys.argv[1]))['metrics']
bad={key:metrics.get('benchmark_'+key,{}).get('count',0) for key in
     ('client_error','server_error','timeout','transport_error')}
if any(bad.values()):
    raise SystemExit(f'unexpected request outcomes: {bad}')
if sys.argv[2] == 'fanout':
    sockets={key:metrics.get('benchmark_socket_'+key,{}).get('count',0) for key in
             ('attempted','opened','confirmed','failed','invalidations')}
    if (sockets['failed'] or sockets['attempted'] != int(sys.argv[3]) or
            sockets['opened'] != sockets['attempted'] or
            sockets['confirmed'] != sockets['attempted'] or not sockets['invalidations']):
        raise SystemExit(f'fanout incomplete: {sockets}')
PY
printf 'k6_exit=%s closer_exit=%s verify_exit=%s profile_exit=%s cpu_profile_exit=%s\nresult_dir=%s\n' "$k6_exit" "$closer_exit" "$verify_exit" "$profile_exit" "$cpu_profile_exit" "$result_dir"
if (( k6_exit || closer_exit || verify_exit || profile_exit || cpu_profile_exit )); then exit 1; fi
