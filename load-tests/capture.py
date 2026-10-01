#!/usr/bin/env python3
"""Record a bounded environment/telemetry snapshot adjacent to one k6 result."""
import argparse
import datetime as dt
import json
import os
import pathlib
import platform
import subprocess
import urllib.parse


def run(*command):
    process = subprocess.run(command, text=True, capture_output=True, check=True)
    return process.stdout.strip()


def optional_run(*command):
    process = subprocess.run(command, text=True, capture_output=True)
    return process.stdout.strip() if process.returncode == 0 else None


def prometheus(expression):
    url = "http://127.0.0.1:9090/api/v1/query?" + urllib.parse.urlencode({"query": expression})
    return json.loads(run("docker", "compose", "exec", "-T", "prometheus", "wget", "-qO-", url))["data"]["result"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--stage", choices=["before", "during", "after"], required=True)
    parser.add_argument("--result-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    fixture = json.loads(args.manifest.read_text())
    ids = ",".join(str(int(id)) for id in fixture["auctions"])
    sql = ("SELECT json_build_object('sessions', (SELECT count(*) FROM pg_stat_activity WHERE datname=current_database()), "
           "'active', (SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state='active'), "
           "'lock_waiters', (SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'), "
           "'wait_events', (SELECT coalesce(json_object_agg(wait_name, n), '{}'::json) FROM "
           "(SELECT coalesce(wait_event_type || ':' || wait_event, 'none') wait_name, count(*) n "
           "FROM pg_stat_activity WHERE datname=current_database() GROUP BY 1) waits), "
           "'blocked_sessions', (SELECT count(*) FROM pg_stat_activity "
           "WHERE datname=current_database() AND cardinality(pg_blocking_pids(pid)) > 0), "
           "'fixture_sidekiq_pending', (SELECT count(*) FROM outbox_events WHERE auction_id IN (" + ids + ") AND published_at IS NULL), "
           "'fixture_kafka_pending', (SELECT count(*) FROM outbox_events WHERE auction_id IN (" + ids + ") AND kafka_published_at IS NULL))")
    data = {"stage": args.stage, "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "run_id": fixture["run_id"], "git_sha": run("git", "rev-parse", "HEAD"),
            "pg_state": json.loads(run("docker", "compose", "exec", "-T", "db", "psql", "-U", "hammerfall",
                                       "-d", "hammerfall_development", "-Atc", sql)),
            "docker_stats": [json.loads(line) for line in run("docker", "stats", "--no-stream", "--format", "{{json .}}").splitlines()],
            "running_containers": [json.loads(line) for line in run("docker", "ps", "--format", "{{json .}}").splitlines()],
            "host_loadavg": pathlib.Path("/proc/loadavg").read_text().strip(),
            "host_mem_available_kib": next((int(line.split()[1]) for line in pathlib.Path("/proc/meminfo").read_text().splitlines()
                                             if line.startswith("MemAvailable:")), None),
            "api_open_fds": optional_run("docker", "compose", "exec", "-T", "api", "sh", "-c", "ls /proc/1/fd | wc -l"),
            "prometheus": {name: prometheus(query) for name, query in {
                "lock_wait_bucket": "sum by (le, operation) (hammerfall_auction_lock_wait_duration_seconds_bucket)",
                "bid_processing_bucket": "sum by (le, operation, result) (hammerfall_bid_processing_duration_seconds_bucket)",
                "db_checkout_bucket": "sum by (le) (hammerfall_db_checkout_duration_seconds_bucket)",
                "db_pool_wait_bucket": "sum by (le) (hammerfall_db_pool_wait_duration_seconds_bucket)",
                "db_pool_busy": "hammerfall_db_pool_busy",
                "db_pool_idle": "hammerfall_db_pool_idle",
                "db_pool_waiting": "hammerfall_db_pool_waiting",
                "publisher_duration_bucket": "sum by (le, channel) (hammerfall_outbox_publish_duration_seconds_bucket)",
                "outbox_pending": "hammerfall_outbox_pending_events",
                "outbox_oldest_age": "hammerfall_outbox_oldest_event_age_seconds",
                "kafka_lag": "hammerfall_kafka_consumer_lag",
                "sidekiq_queue": "hammerfall_sidekiq_queue_depth",
                "websocket_broadcasts": "hammerfall_websocket_broadcasts_total",
                "websocket_lag_bucket": "sum by (le) (hammerfall_websocket_server_broadcast_lag_seconds_bucket)",
                "extensions": "hammerfall_auction_extensions_total",
                "close_lag_bucket": "sum by (le) (hammerfall_auction_close_lag_seconds_bucket)",
                "reconciliation": "hammerfall_projection_drift_total",
            }.items()}}
    if args.stage == "before":
        services = run("docker", "compose", "ps", "-q").splitlines()
        inspect = json.loads(run("docker", "inspect", *services))
        data["environment"] = {
            "host_os": platform.platform(), "cpu_model": next((line.split(":", 1)[1].strip() for line in
                 pathlib.Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
            "logical_cpus": os.cpu_count(),
            "mem_total_kib": next((int(line.split()[1]) for line in pathlib.Path("/proc/meminfo").read_text().splitlines()
                                   if line.startswith("MemTotal:")), None),
            "docker_version": run("docker", "version", "--format", "{{.Server.Version}}"),
            "k6_version": run("docker", "run", "--rm", "grafana/k6:1.8.1", "version"),
            "postgres_settings": run("docker", "compose", "exec", "-T", "db", "psql", "-U", "hammerfall",
                                     "-d", "hammerfall_development", "-Atc",
                                     "SHOW max_connections; SHOW shared_buffers; SHOW work_mem; SHOW lock_timeout; SHOW statement_timeout;").splitlines(),
            "api_otel_enabled": run("docker", "compose", "exec", "-T", "api", "printenv", "OTEL_ENABLED"),
            "api_open_file_limit": run("docker", "compose", "exec", "-T", "api", "sh", "-c", "ulimit -n"),
            "api_rails_max_threads": run("docker", "compose", "exec", "-T", "api", "sh", "-c", "printf '%s' \"${RAILS_MAX_THREADS:-3}\""),
            "api_db_pool": run("docker", "compose", "exec", "-T", "api", "sh", "-c", "printf '%s' \"${DATABASE_POOL:-${RAILS_MAX_THREADS:-3}}\""),
            "sidekiq_concurrency": 2,
            "redis_config": run("docker", "compose", "exec", "-T", "redis", "redis-cli", "CONFIG", "GET", "maxmemory", "appendonly").splitlines(),
            "kafka_topic_partitions": 3,
            "container_limits": [{"name": entry["Name"], "memory_bytes": entry["HostConfig"]["Memory"],
                                  "nano_cpus": entry["HostConfig"]["NanoCpus"],
                                  "cpu_quota": entry["HostConfig"]["CpuQuota"]} for entry in inspect],
            "manifest": {key: value for key, value in fixture.items() if key != "duplicate_key"},
        }
    args.result_dir.mkdir(parents=True, exist_ok=True)
    target = args.result_dir / f"{args.stage}.json"
    target.write_text(json.dumps(data, indent=2) + "\n")
    print(target)


if __name__ == "__main__":
    main()
