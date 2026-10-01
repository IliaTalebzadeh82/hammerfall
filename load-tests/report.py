#!/usr/bin/env python3
"""Turn retained machine output into a concise, auditable run report."""
import argparse
import json
import pathlib


def metric(summary, name, key="count"):
    return summary.get(name, {}).get(key)


def fmt(value, digits=2):
    return "—" if value is None else f"{value:.{digits}f}"


def bucket_delta(before, after, source, labels):
    def table(snapshot):
        rows = snapshot["prometheus"].get(source, [])
        return {tuple(sorted(row["metric"].items())): float(row["value"][1]) for row in rows}
    old, new = table(before), table(after)
    result = {}
    for key, value in new.items():
        parts = dict(key)
        if all(parts.get(k) == v for k, v in labels.items()):
            result[parts["le"]] = value - old.get(key, 0)
    return result


def bucket_bounds(values):
    count = values.get("+Inf", 0)
    if count <= 0 or any(value < 0 for value in values.values()):
        return count, [None] * 3
    bounds = sorted((float(key), value) for key, value in values.items() if key != "+Inf")
    return count, [next((bound for bound, n in bounds if n >= count * q), None) for q in (.5, .95, .99)]


def gauge_by(snapshot, source, label):
    result = {}
    for row in snapshot["prometheus"].get(source, []):
        name = row["metric"].get(label, "total")
        result[name] = result.get(name, 0) + float(row["value"][1])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("result_dir", type=pathlib.Path)
    args = parser.parse_args()
    path = args.result_dir
    summary = json.loads((path / "summary.json").read_text())["metrics"]
    before = json.loads((path / "before.json").read_text())
    after = json.loads((path / "after.json").read_text())
    during = json.loads((path / "during.json").read_text()) if (path / "during.json").exists() else None
    verify = json.loads((path / "verify.json").read_text())
    env = before["environment"]
    fixture = env["manifest"]
    measurement_command = next((line.removeprefix("measurement: ") for line in
                                (path / "commands.txt").read_text().splitlines()
                                if line.startswith("measurement: ")), "unknown")
    iterations = metric(summary, "iterations") or 0
    command_count = None
    maximum_count = None
    if fixture["scenario"] == "normal":
        cycles, remainder = divmod(iterations, 10)
        expected_bids = 2 * cycles + sum(slot < remainder for slot in (7, 8))
        expected_maxima = cycles
        observed_mutations = sum(metric(summary, name) or 0 for name in
                                 ("benchmark_mutation_accepted", "benchmark_mutation_domain_rejected"))
        if observed_mutations == expected_bids + expected_maxima:
            command_count, maximum_count = expected_bids, expected_maxima
    elif fixture["scenario"] in ("hot", "distributed", "closing", "challenge"):
        command_count = iterations
    elif fixture["scenario"] == "duplicate":
        command_count = iterations
    elif fixture["scenario"] == "burst":
        command_count = iterations * 2
    lines = [f"# {fixture['scenario']} — {fixture['run_id']}", "",
             f"Recorded from commit `{before['git_sha']}` at {before['captured_at_utc']} UTC.", "",
             "## Environment and method", "",
             f"- Host: {env['host_os']}; {env['cpu_model']}; {env['logical_cpus']} logical CPUs; {env['mem_total_kib'] / 1048576:.1f} GiB RAM.",
             f"- Docker {env['docker_version']}; {env['k6_version']}; Compose containers have the recorded resource limits in `before.json` (zero means unset).",
             f"- PostgreSQL max connections/shared buffers/work mem/lock timeout/statement timeout: {', '.join(env['postgres_settings'])}; API Puma threads: {env['api_rails_max_threads']}, DB pool: {env.get('api_db_pool', env['api_rails_max_threads'])}; Sidekiq concurrency: {env['sidekiq_concurrency']}.",
             f"- Kafka topic: {env['kafka_topic_partitions']} partitions; Redis settings: {env['redis_config']}; API OTEL_ENABLED={env['api_otel_enabled']}.",
             f"- Fixture: {len(fixture['auctions'])} auction(s), {len(fixture['users'])} bidder(s), starting price {fixture['starting_price']} cents, increment {fixture['minimum_increment']} cents, ends at {fixture['ends_at']}.",
             "- Separate read-only warm-up: 1 VU for 5 seconds. Exact commands and load configuration are in `commands.txt`; raw summary, log and snapshots are adjacent.",
             f"- Measurement command: `{measurement_command}`; achieved VUs: {metric(summary, 'vus_max', 'max') or 'see summary.json'}.",
             "", "## Results", "",
             "| Measure | Count/rate | p50 | p95 | p99 |", "|---|---:|---:|---:|---:|",]
    for label, name, count_name in [
        ("All HTTP requests", "http_req_duration", "http_reqs"),
        ("Bid HTTP duration", "benchmark_bid_duration", "_derived_bid"),
        ("Maximum HTTP duration", "benchmark_maximum_duration", "_derived_maximum"),
        ("Replay HTTP duration", "benchmark_replay_duration", "benchmark_idempotent_replay"),
    ]:
        if name in summary:
            count = (command_count if count_name == "_derived_bid" else
                     maximum_count if count_name == "_derived_maximum" else
                     metric(summary, count_name))
            count = count if count is not None else "see outcome counts"
            lines.append(f"| {label} | {count} | {fmt(metric(summary, name, 'med'))} ms | {fmt(metric(summary, name, 'p(95)'))} ms | {fmt(metric(summary, name, 'p(99)'))} ms |")
    lines += ["", f"Achieved request rate: {fmt(metric(summary, 'http_reqs', 'rate'))}/s; iterations: {metric(summary, 'iterations')}; unexpected HTTP failures: {metric(summary, 'http_req_failed', 'passes') or 0}.",
              "", "| Classified outcome | Count |", "|---|---:|"]
    for label, name in [("Accepted HTTP (including reads)", "benchmark_accepted"),
                        ("Accepted mutations", "benchmark_mutation_accepted"),
                        ("Domain rejections", "benchmark_domain_rejected"),
                        ("Idempotent replays", "benchmark_idempotent_replay"),
                        ("Conflicts", "benchmark_conflict"),
                        ("Client errors", "benchmark_client_error"),
                        ("Server errors", "benchmark_server_error"),
                        ("Timeouts", "benchmark_timeout"),
                        ("Transport errors", "benchmark_transport_error")]:
        lines.append(f"| {label} | {metric(summary, name) or 0} |")
    lines += ["", "## Database and telemetry", "",
              f"Authoritative checker: {len(verify['failures'])} failure(s), {sum(x['bids'] for x in verify['auctions'])} bid rows, {sum(x['maximum_bids'] for x in verify['auctions'])} maximum instructions. See `verify.json` for each auction's sequence/price/leader/revision and pending outbox counts."]
    if fixture["scenario"] in ("closing", "challenge"):
        closing = verify["auctions"][0]["closing"]
        if closing:
            lines.append(f"- Closing: {len(closing['extensions'])} recorded extensions; original end {closing['original_ends_at']}; final end {verify['auctions'][0]['ends_at']}; closed at {closing['closed_at']}; close lag {closing['close_lag_seconds']} s; leader/winner {verify['auctions'][0]['leader_id']}/{verify['auctions'][0]['winner_id']}.")
            lines.append("- Extension revisions and observation times are in `verify.json`; closer polling observations are in `closer-observations.json`. Event observation time follows the DB decision and is not itself the decision timestamp.")
            lines.append(f"- PostgreSQL outbox event time preceded the prior effective deadline for {closing['event_observed_before_prior_deadline']} mutation events; {closing['timing_inconclusive_events']} event time(s) cannot establish eligibility after a queued decision.")
    if fixture["scenario"] == "fanout":
        lines += ["", "## Action Cable client observations", "",
                  "These receipts are k6 client observations of invalidation hints, not proof of universal browser delivery or authoritative state.", ""]
        for label, name in [("Attempted sockets", "benchmark_socket_attempted"),
                            ("Opened sockets", "benchmark_socket_opened"),
                            ("Confirmed subscriptions", "benchmark_socket_confirmed"),
                            ("Failed sockets", "benchmark_socket_failed"),
                            ("Invalidations received", "benchmark_socket_invalidations"),
                            ("Disconnected sockets", "benchmark_socket_disconnected")]:
            lines.append(f"- {label}: {metric(summary, name) or 0}.")
    if fixture["scenario"] == "burst":
        lines.append("- Simultaneous first-wave and delayed replay latency are in `summary.json` under `benchmark_burst_initial_duration` and `benchmark_burst_later_duration`; the former mixes original ownership with concurrent idempotency waiters.")
    for label, snapshot in [("Before", before), ("During", during), ("After", after)]:
        if snapshot:
            state = snapshot["pg_state"]
            api = next((x for x in snapshot["docker_stats"] if "-api-" in x["Name"]), None)
            cpu = f"; API CPU {api['CPUPerc']}, memory {api['MemUsage']}" if api else ""
            k6_container = next((x for x in snapshot.get("running_containers", []) if "grafana/k6:" in x.get("Image", "")), None)
            k6_stats = next((x for x in snapshot["docker_stats"] if k6_container and x["Name"] == k6_container["Names"]), None)
            k6_text = f"; k6 CPU {k6_stats['CPUPerc']}, memory {k6_stats['MemUsage']}" if k6_stats else ""
            lines.append(f"- {label}: PostgreSQL {state['sessions']} sessions, {state['active']} active, {state['lock_waiters']} lock waiters; fixture Sidekiq/Kafka pending {state['fixture_sidekiq_pending']}/{state['fixture_kafka_pending']}{cpu}{k6_text}.")
            pending = gauge_by(snapshot, "outbox_pending", "channel")
            oldest = gauge_by(snapshot, "outbox_oldest_age", "channel")
            lag = gauge_by(snapshot, "kafka_lag", "consumer_group")
            if pending or oldest or lag:
                lines.append(f"  Prometheus snapshot: global outbox pending {pending}, oldest age seconds {oldest}, summed Kafka lag {lag}; gauges are asynchronous and can be stale.")
    for label, source, labels in [
        ("Auction lock wait / place_bid", "lock_wait_bucket", {"operation": "place_bid"}),
        ("Bid processing / accepted", "bid_processing_bucket", {"operation": "place_bid", "result": "accepted"}),
        ("Bid processing / rejected", "bid_processing_bucket", {"operation": "place_bid", "result": "rejected"}),
        ("Publisher delivery / Kafka", "publisher_duration_bucket", {"channel": "kafka"}),
        ("Publisher delivery / Sidekiq", "publisher_duration_bucket", {"channel": "sidekiq"}),
    ]:
        count, bounds = bucket_bounds(bucket_delta(before, after, source, labels))
        if count:
            if count < 20:
                lines.append(f"- {label}: {int(count)} observed histogram samples; too few for useful percentile reporting.")
            else:
                formatted = [fmt(x * 1000) + " ms" if x is not None else "above finite buckets"
                             for x in bounds]
                lines.append(f"- {label}: {int(count)} observed histogram samples; p50/p95/p99 **bucket upper bounds** {', '.join(formatted)}.")
    lines += ["", "## Interpretation and limits", "",
              "This is one short local run on a shared host. It establishes no production capacity or SLO. A single during-run PostgreSQL sample can miss a peak; Prometheus counters can lag k6 at snapshot time. Histogram figures are bucket bounds, not exact percentiles. Kafka lag gauges can remain stale while idle. Compare only like configurations and repeat before concluding a bottleneck.", ""]
    (path / "report.md").write_text("\n".join(lines))
    print(path / "report.md")


if __name__ == "__main__":
    main()
