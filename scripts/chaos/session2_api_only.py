#!/usr/bin/env python3
"""Direct derived-state observation while the API container is stopped."""
import json
import time

from run import DEADLINE, Run, compose, require
from session2_api import offline_probe, wait_api


def redis_projection(auction_id):
    raw = compose("exec", "-T", "redis", "redis-cli", "--raw", "GET",
                  f"hammerfall:auction-public:v1:{auction_id}")
    return json.loads(raw) if raw else None


def service_states():
    rows = [json.loads(line) for line in compose("ps", "--all", "--format", "json").splitlines()]
    wanted = {"api", "kafka-outbox-publisher", "outbox-publisher", "kafka-audit-consumer",
              "kafka-projection-consumer", "sidekiq", "reconciliation-scheduler"}
    return {row["Service"]: row["State"] for row in rows if row["Service"] in wanted}


def main():
    run = Run("session2-api-only-direct")
    try:
        run.fixture(); run.bid()
        run.wait("baseline", run.converged)
        run.stop("kafka-outbox-publisher")
        run.stop("outbox-publisher")
        run.bid()
        before = run.snapshot("before_api_stop")["postgresql"]
        require(before["kafka_pending"] > 0 and before["sidekiq_pending"] > 0,
                "fixture lacks both outbox backlogs")
        run.stop("api")
        require(service_states()["api"] == "exited", "API remained available")
        compose("up", "-d", "--no-deps", "kafka-outbox-publisher", "outbox-publisher", timeout=90)
        run.stopped.remove("kafka-outbox-publisher")
        run.stopped.remove("outbox-publisher")
        start = time.monotonic()
        while time.monotonic() - start < DEADLINE:
            state = offline_probe(run)
            redis = redis_projection(run.auction_id)
            if (state["kafka_pending"] == state["sidekiq_pending"] == 0 and
                state["audit_effects"] == state["outbox_count"] and redis and
                redis.get("public_revision") == state["public_revision"]):
                break
            time.sleep(5)
        else:
            raise TimeoutError("derived paths did not converge while API was down")
        public_match = all(redis["data"].get(key) == value for key, value in state["public_data"].items())
        require(public_match, "Redis public projection differs from PostgreSQL")
        observed = {"postgresql": state, "redis_revision": redis["public_revision"],
                    "redis_public_fields_match": public_match, "services": service_states(),
                    "elapsed_seconds": round(time.monotonic() - start, 2)}
        (run.dir / "during_api_outage.json").write_text(json.dumps(observed, indent=2) + "\n")
        require(observed["services"]["api"] == "exited" and all(
            observed["services"][name] == "running" for name in
            ["kafka-outbox-publisher", "outbox-publisher", "kafka-audit-consumer",
             "kafka-projection-consumer", "sidekiq", "reconciliation-scheduler"]),
            "expected independent processes were not running")
        run.record("derived_work_continued_without_api",
                   elapsed_seconds=observed["elapsed_seconds"])
        run.start("api")
        wait_api()
        run.wait("recovered", run.converged)
        run.verify()
        run.record("pass")
    except Exception as error:
        run.record("fail", error_type=type(error).__name__, detail=str(error)[:500])
        raise
    finally:
        for service in reversed(run.stopped):
            try:
                compose("start", service, timeout=90)
                run.record("cleanup_started", service=service)
            except Exception as error:
                run.record("cleanup_failed", service=service, detail=str(error)[:300])
        print(run.dir.relative_to(ROOT))


if __name__ == "__main__":
    main()
