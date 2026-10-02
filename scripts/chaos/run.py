#!/usr/bin/env python3
"""Bounded, isolated Phase 16 Compose failure campaigns. Run from repo root."""
import argparse
import datetime as dt
import json
import pathlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "http://127.0.0.1:3001"
DEADLINE = 120


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def command(*args, timeout=40, env=None):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True,
                            timeout=timeout, env=env)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:4])}: exit {result.returncode}: "
                           f"{(result.stderr or result.stdout)[-800:]}")
    return result.stdout.strip()


def compose(*args, timeout=40):
    return command("docker", "compose", *args, timeout=timeout)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def http(method, path, body=None, key=None):
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Idempotency-Key"] = key
    request = urllib.request.Request(BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{method} {path}: HTTP {error.code} {error.read().decode()[:500]}") from error


class Run:
    def __init__(self, scenario):
        self.scenario = scenario
        self.id = f"p16-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"
        self.dir = ROOT / "docs" / "chaos" / self.id
        self.dir.mkdir(parents=True)
        self.events = []
        self.stopped = []
        self.auction_id = None
        self.bid_count = 0
        self.record("start", scenario=scenario, git_sha=command("git", "rev-parse", "HEAD"))

    def record(self, action, **data):
        self.events.append({"at_utc": now(), "action": action, **data})
        (self.dir / "timeline.json").write_text(json.dumps(self.events, indent=2) + "\n")

    def fixture(self):
        with urllib.request.urlopen(BASE + "/up", timeout=5) as response:
            if response.status != 200:
                raise RuntimeError("API health check failed")
        user = http("POST", "/api/v1/users", {"user": {"name": f"{self.id}-bidder"}})["data"]
        current = dt.datetime.now(dt.timezone.utc)
        auction = http("POST", "/api/v1/auctions", {"auction": {
            "title": self.id, "description": "Phase 16 isolated chaos fixture",
            "starting_price": 10000, "minimum_increment": 100,
            "starts_at": (current - dt.timedelta(minutes=2)).isoformat(),
            "ends_at": (current + dt.timedelta(minutes=20)).isoformat()}})["data"]
        self.auction_id, self.user_id = auction["id"], user["id"]
        http("POST", f"/api/v1/auctions/{self.auction_id}/schedule")
        http("POST", f"/api/v1/auctions/{self.auction_id}/activate")
        self.record("fixture", auction_id=self.auction_id, user_id=self.user_id)

    def bid(self):
        self.bid_count += 1
        amount = 10000 + self.bid_count * 100
        result = http("POST", f"/api/v1/auctions/{self.auction_id}/bids",
            {"bid": {"bidder_id": self.user_id, "amount": amount}}, key=str(uuid.uuid4()))
        self.record("bid_accepted", amount=amount, bid_id=result["data"]["id"])

    def probe(self):
        output = compose("exec", "-T", "-e", f"CHAOS_AUCTION_ID={self.auction_id}",
            "api", "bin/rails", "runner", "script/chaos_probe.rb", timeout=45)
        return json.loads(output.splitlines()[-1])

    def snapshot(self, stage):
        aid = self.auction_id
        result = {"at_utc": now(), "postgresql": self.probe(),
            "ordinary_get": http("GET", f"/api/v1/auctions/{aid}"),
            "eventual_get": http("GET", f"/api/v1/auctions/{aid}/public-state"),
            "telemetry": self.telemetry()}
        (self.dir / f"{stage}.json").write_text(json.dumps(result, indent=2) + "\n")
        self.record("snapshot", stage=stage,
            revision=result["postgresql"]["public_revision"],
            sidekiq_pending=result["postgresql"]["sidekiq_pending"],
            kafka_pending=result["postgresql"]["kafka_pending"],
            audit_effects=result["postgresql"]["audit_effects"],
            eventual_source=result["eventual_get"]["meta"]["source"])
        return result

    def telemetry(self):
        # Global, sampled diagnostics; the direct fixture probe remains the verifier.
        expressions = {
            "outbox_pending": "hammerfall_outbox_pending_events",
            "outbox_failures": "hammerfall_outbox_publish_failures_total",
            "projection_drift": "hammerfall_projection_drift_total",
            "kafka_lag": "hammerfall_kafka_consumer_lag",
        }
        samples = {}
        for name, expression in expressions.items():
            url = "http://127.0.0.1:9090/api/v1/query?" + urllib.parse.urlencode({"query": expression})
            try:
                raw = compose("exec", "-T", "prometheus", "wget", "-qO-", url, timeout=8)
                rows = json.loads(raw)["data"]["result"]
                samples[name] = [{"channel": row["metric"].get("channel"),
                                  "consumer_group": row["metric"].get("consumer_group"),
                                  "partition": row["metric"].get("partition"),
                                  "sampled_at": row["value"][0], "value": row["value"][1]}
                                 for row in rows]
            except (RuntimeError, subprocess.TimeoutExpired, KeyError, ValueError):
                samples[name] = "unavailable"
        return samples

    def wait_log_result(self, service, event_id, result, since, timeout=60):
        started = time.monotonic()
        while time.monotonic() - started < timeout:
            logs = compose("logs", "--no-color", "--since", since, service, timeout=12)
            matches = [line for line in logs.splitlines() if f'"event_id":"{event_id}"' in line and
                       f'"result":"{result}"' in line]
            if matches:
                (self.dir / f"{service}-{result}.log").write_text("\n".join(matches[-3:]) + "\n")
                self.record("consumer_result", service=service, result=result, event_id=event_id)
                return
            time.sleep(3)
        raise TimeoutError(f"{service} did not report {result} for {event_id}")

    def wait(self, label, predicate, timeout=DEADLINE):
        started = time.monotonic()
        while True:
            state = self.snapshot(label)
            if predicate(state):
                self.record("converged", stage=label, elapsed_seconds=round(time.monotonic() - started, 2))
                return state
            if time.monotonic() - started > timeout:
                raise TimeoutError(f"{label}: no convergence within {timeout} seconds")
            time.sleep(5)

    def converged(self, state):
        pg = state["postgresql"]
        eventual = state["eventual_get"]
        return (not pg["failures"] and pg["sidekiq_pending"] == 0 and
            pg["kafka_pending"] == 0 and pg["audit_effects"] == pg["outbox_count"] and
            eventual["meta"]["source"] == "redis" and
            all(eventual["data"].get(key) == value for key, value in pg["public_data"].items()) and
            eventual["data"].get("public_revision") == pg["public_revision"])

    def stop(self, service):
        compose("stop", service, timeout=45)
        self.stopped.append(service)
        self.record("service_stopped", service=service)

    def start(self, service):
        compose("start", service, timeout=90)
        self.stopped.remove(service)
        self.record("service_started", service=service)

    def verify(self):
        manifest = {"run_id": self.id, "scenario": "normal", "auctions": [self.auction_id],
                    "users": [self.user_id]}
        output = compose("exec", "-T", "-e", "BENCHMARK_MANIFEST=" + json.dumps(manifest),
            "api", "bin/rails", "runner", "script/benchmark_verify.rb", timeout=45)
        result = json.loads(output.splitlines()[-1])
        (self.dir / "verify.json").write_text(json.dumps(result, indent=2) + "\n")
        if result["failures"]:
            raise RuntimeError(f"PostgreSQL verifier: {result['failures']}")
        self.record("postgresql_verified", bid_count=result["auctions"][0]["bids"])

    def run(self):
        self.fixture()
        self.bid()
        self.wait("baseline", self.converged)
        if self.scenario == "baseline":
            pass
        elif self.scenario == "redis":
            self.stop("redis")
            self.bid()
            during = self.snapshot("during")
            require(during["eventual_get"]["meta"]["source"] == "postgresql",
                    "Redis outage did not use PostgreSQL fallback")
            require(during["postgresql"]["bid_count"] == self.bid_count,
                    "accepted bid missing during Redis outage")
            self.start("redis")
            # Delete only this fixture's derived key. Sidekiq shares this Redis.
            compose("exec", "-T", "redis", "redis-cli", "DEL",
                f"hammerfall:auction-public:v1:{self.auction_id}")
            self.record("projection_key_deleted", auction_id=self.auction_id)
            compose("start", "sidekiq", "kafka-projection-consumer")
            self.record("dependent_workers_started", services=["sidekiq", "kafka-projection-consumer"])
            self.wait("recovered", self.converged)
            # Explicitly prove detection and safe repair of a missing key.
            compose("exec", "-T", "redis", "redis-cli", "DEL",
                f"hammerfall:auction-public:v1:{self.auction_id}")
            repair = compose("exec", "-T", "-e", f"CHAOS_AUCTION_ID={self.auction_id}",
                "api", "bin/rails", "runner", "script/chaos_reconcile.rb", timeout=45)
            self.record("targeted_reconciliation", result=json.loads(repair.splitlines()[-1]))
            self.wait("reconciled", self.converged)
        elif self.scenario == "kafka":
            self.stop("kafka")
            self.bid(); self.bid()
            time.sleep(8)  # allow a real failed publish and retry counter
            during = self.snapshot("during")
            require(during["postgresql"]["kafka_pending"] > 0,
                    "broker outage did not leave Kafka intent pending")
            require(during["postgresql"]["bid_count"] == self.bid_count,
                    "accepted bid missing during broker outage")
            self.start("kafka")
            self.wait("recovered", self.converged)
        elif self.scenario == "worker":
            self.stop("outbox-publisher")
            self.stop("sidekiq")
            self.bid(); self.bid()
            during = self.snapshot("during")
            require(during["postgresql"]["sidekiq_pending"] > 0,
                    "worker outage did not leave Sidekiq intent pending")
            self.start("sidekiq")
            self.start("outbox-publisher")
            self.wait("recovered", self.converged)
        elif self.scenario == "publisher":
            self.stop("kafka")
            self.bid(); self.bid()
            before = self.snapshot("during")
            require(before["postgresql"]["kafka_pending"] > 0,
                    "publisher crash fixture has no Kafka backlog")
            compose("kill", "-s", "SIGKILL", "kafka-outbox-publisher")
            self.record("publisher_sigkill", service="kafka-outbox-publisher")
            crashed = self.snapshot("crashed")
            require(crashed["postgresql"]["outbox_event_ids"] == before["postgresql"]["outbox_event_ids"],
                    "publisher crash changed event identities")
            self.start("kafka")
            compose("start", "kafka-outbox-publisher")
            self.record("publisher_started", service="kafka-outbox-publisher")
            recovered = self.wait("recovered", self.converged)
            require(recovered["postgresql"]["outbox_event_ids"] == before["postgresql"]["outbox_event_ids"],
                    "publisher recovery changed event identities")
        elif self.scenario == "duplicate":
            before = self.snapshot("before_replay")
            event_id = before["postgresql"]["latest_event_id"]
            since = now()
            replay = compose("exec", "-T", "-e", f"CHAOS_EVENT_ID={event_id}",
                "kafka-outbox-publisher", "bin/rails", "runner", "script/chaos_replay_event.rb")
            self.record("broker_replay", result=json.loads(replay.splitlines()[-1]))
            self.wait_log_result("kafka-audit-consumer", event_id, "duplicate", since)
            self.wait_log_result("kafka-projection-consumer", event_id, "duplicate", since)
            # Audit receipt/effect counts must stay fixed after consumer progress.
            self.wait("recovered", lambda s: self.converged(s) and
                s["postgresql"]["audit_effects"] == before["postgresql"]["audit_effects"])
        self.verify()
        final = self.snapshot("final")
        if not self.converged(final):
            raise RuntimeError("final derived state did not converge")
        self.record("pass")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", choices=["baseline", "redis", "kafka", "worker", "publisher", "duplicate"])
    args = parser.parse_args()
    run = Run(args.scenario)
    try:
        run.run()
    except Exception as error:
        run.record("fail", error_type=type(error).__name__, detail=str(error)[:800])
        raise
    finally:
        for service in reversed(run.stopped):
            try:
                compose("start", service, timeout=90)
                run.record("cleanup_started", service=service)
            except Exception as error:
                run.record("cleanup_failed", service=service, detail=str(error)[:500])
        print(run.dir.relative_to(ROOT))


if __name__ == "__main__":
    main()
