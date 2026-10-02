#!/usr/bin/env python3
"""Phase 16 API process death, same-key retry, and API-only outage."""
import json
import time
import urllib.error
import urllib.request
import uuid

from run import BASE, DEADLINE, ROOT, Run, compose, http, require


def bid(run, key, amount, bidder_id=None, expect_response=True):
    body = json.dumps({"bid": {"bidder_id": bidder_id or run.user_id,
                                "amount": amount}}).encode()
    request = urllib.request.Request(BASE + f"/api/v1/auctions/{run.auction_id}/bids",
        data=body, method="POST", headers={"Content-Type": "application/json",
                                           "Idempotency-Key": key})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            result = {"status": response.status,
                      "replayed": response.headers.get("Idempotency-Replayed") == "true",
                      "body": json.load(response)}
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as error:
        if expect_response:
            raise
        run.record("response_lost", error_type=type(error).__name__)
        return None
    require(expect_response, "faulted API unexpectedly returned a response")
    return result


def wait_api(timeout=90):
    started = time.monotonic()
    while time.monotonic() - started < timeout:
        try:
            with urllib.request.urlopen(BASE + "/up", timeout=3) as response:
                if response.status == 200:
                    return round(time.monotonic() - started, 2)
        except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
            pass
        time.sleep(2)
    raise TimeoutError("API did not become healthy within 90 seconds")


def offline_probe(run):
    output = compose("exec", "-T", "-e", f"CHAOS_AUCTION_ID={run.auction_id}",
        "-e", f"CHAOS_USER_ID={run.user_id}", "auction-closer", "bin/rails", "runner",
        "script/chaos_probe.rb", timeout=45)
    return json.loads(output.splitlines()[-1])


def api_status(run, stage):
    rows = [json.loads(line) for line in compose("ps", "--all", "--format", "json", "api").splitlines()]
    state = [{"state": row.get("State"), "exit_code": row.get("ExitCode")}
             for row in rows if row.get("Service") == "api"]
    (run.dir / f"api-{stage}.json").write_text(json.dumps(state, indent=2) + "\n")
    run.record("api_status", stage=stage, state=state)
    return state


def fault_api(run, boundary):
    # Override contains only public fixture ID. Recreating from the base file
    # clears the fault variables after each crash.
    override = run.dir / "api-fault.yml"
    override.write_text("services:\n  api:\n    environment:\n"
        "      HAMMERFALL_CHAOS_CONFIRM: phase-16-local-crash\n"
        f"      HAMMERFALL_CHAOS_CRASH_BOUNDARY: {boundary}\n"
        f"      HAMMERFALL_CHAOS_AUCTION_ID: '{run.auction_id}'\n")
    compose("-f", "docker-compose.yml", "-f", str(override.relative_to(ROOT)),
        "up", "-d", "--force-recreate", "--no-deps", "api", timeout=90)
    run.record("api_fault_armed", boundary=boundary)
    wait_api()


def restore_api(run):
    compose("up", "-d", "--force-recreate", "--no-deps", "api", timeout=90)
    elapsed = wait_api()
    run.record("api_restored", elapsed_seconds=elapsed)


def equal_authority(before, after):
    fields = ["bid_count", "last_bid_sequence", "public_revision", "outbox_count",
              "maximum_count", "idempotency_count", "idempotency_completed", "public_data"]
    return all(before[field] == after[field] for field in fields)


def run_campaign(run):
    run.fixture(); run.bid()
    max_bidder = http("POST", "/api/v1/users", {"user": {"name": run.id + "-max"}})["data"]["id"]
    tie_bidder = http("POST", "/api/v1/users", {"user": {"name": run.id + "-tie"}})["data"]["id"]
    http("PUT", f"/api/v1/auctions/{run.auction_id}/maximum-bid",
        {"maximum_bid": {"bidder_id": max_bidder, "maximum_amount": 15000}}, key=str(uuid.uuid4()))
    before_restart = run.wait("before_restart", run.converged)["postgresql"]
    require(before_restart["maximum_count"] == 1, "maximum baseline missing")
    run.stop("api")
    down = offline_probe(run)
    require(equal_authority(before_restart, down), "API stop changed PostgreSQL authority")
    api_status(run, "stopped")
    run.start("api")
    wait_api()
    restarted = run.snapshot("after_restart")["postgresql"]
    require(equal_authority(before_restart, restarted), "API restart changed auction or command state")
    http("PUT", f"/api/v1/auctions/{run.auction_id}/maximum-bid",
        {"maximum_bid": {"bidder_id": tie_bidder, "maximum_amount": 15000}}, key=str(uuid.uuid4()))
    tie = run.wait("tie_after_restart", run.converged)["postgresql"]
    require(tie["maximum_count"] == 2 and tie["maximum_priorities_unique"] and
            tie["public_data"]["current_leader_id"] == max_bidder,
            "maximum ceiling or earlier priority did not survive API restart")

    # Commit succeeds; the API dies before it can render the response.
    before_a = run.snapshot("before_committed_crash")["postgresql"]
    key_a = str(uuid.uuid4())
    amount_a = before_a["public_data"]["current_price"] + 100
    fault_api(run, "command_committed")
    require(bid(run, key_a, amount_a, expect_response=False) is None,
            "committed crash returned a response")
    api_status(run, "committed_crash")
    committed = offline_probe(run)
    (run.dir / "after_committed_crash.json").write_text(json.dumps(committed, indent=2) + "\n")
    require(committed["bid_count"] > before_a["bid_count"] and
            committed["public_revision"] > before_a["public_revision"] and
            committed["idempotency_completed"] == before_a["idempotency_completed"] + 1,
            "committed command or terminal record missing after response loss")
    original_bid_id = committed["last_bid_id"]
    restore_api(run)
    # Change state before replay to prove the completed outcome is historical.
    later = bid(run, str(uuid.uuid4()), committed["public_data"]["current_price"] + 100,
                bidder_id=tie_bidder)
    require(later["status"] == 201, "later state change failed")
    before_replay = run.probe()
    replay = bid(run, key_a, amount_a)
    after_replay = run.probe()
    require(replay["status"] == 201 and replay["replayed"] and
            replay["body"]["data"]["id"] == original_bid_id and
            equal_authority(before_replay, after_replay),
            "same-key replay re-executed after later state changed")
    run.record("committed_replay_verified", original_bid_id=original_bid_id)

    # The database transaction has written domain rows, then process death
    # forces its open connection to roll back before the terminal outcome.
    before_b = run.snapshot("before_uncommitted_crash")["postgresql"]
    key_b = str(uuid.uuid4())
    amount_b = before_b["public_data"]["current_price"] + 100
    fault_api(run, "command_before_commit")
    require(bid(run, key_b, amount_b, expect_response=False) is None,
            "uncommitted crash returned a response")
    api_status(run, "uncommitted_crash")
    aborted = offline_probe(run)
    (run.dir / "after_uncommitted_crash.json").write_text(json.dumps(aborted, indent=2) + "\n")
    require(equal_authority(before_b, aborted), "uncommitted transaction left partial auction state")
    restore_api(run)
    retry = bid(run, key_b, amount_b)
    require(retry["status"] == 201 and not retry["replayed"],
            "aborted same-key command did not execute normally")
    completed = run.wait("aborted_retry_recovered", run.converged)["postgresql"]
    require(completed["idempotency_completed"] == before_b["idempotency_completed"] + 1,
            "aborted retry did not create exactly one terminal record")
    run.record("aborted_retry_verified")

    # Hold publication briefly, then prove independent workers drain it while
    # only the API is down. Starting this publisher uses --no-deps.
    run.stop("kafka-outbox-publisher")
    bid(run, str(uuid.uuid4()), completed["public_data"]["current_price"] + 100)
    pending = run.probe()
    require(pending["kafka_pending"] > 0, "API-only fixture has no publication backlog")
    run.stop("api")
    down = offline_probe(run)
    require(down["bid_count"] > completed["bid_count"], "committed bid disappeared with API")
    compose("up", "-d", "--no-deps", "kafka-outbox-publisher", timeout=90)
    run.stopped.remove("kafka-outbox-publisher")
    started = time.monotonic()
    while time.monotonic() - started < DEADLINE:
        state = offline_probe(run)
        if state["kafka_pending"] == 0 and state["audit_effects"] == state["outbox_count"]:
            break
        time.sleep(5)
    else:
        raise TimeoutError("independent publication did not drain during API outage")
    run.record("independent_workers_drained", elapsed_seconds=round(time.monotonic() - started, 2))
    run.start("api")
    wait_api()
    run.wait("api_only_recovered", run.converged)
    run.verify()
    final = run.snapshot("final")
    require(run.converged(final), "final derived state did not converge")
    run.record("pass")


def main():
    run = Run("session2-api")
    try:
        run_campaign(run)
    except Exception as error:
        run.record("fail", error_type=type(error).__name__, detail=str(error)[:500])
        raise
    finally:
        # Always clear the temporary hook environment from the API container.
        try:
            restore_api(run)
        except Exception as error:
            run.record("cleanup_api_failed", detail=str(error)[:300])
        for service in reversed(run.stopped):
            if service == "api":
                continue
            try:
                compose("start", service, timeout=90)
                run.record("cleanup_started", service=service)
            except Exception as error:
                run.record("cleanup_failed", service=service, detail=str(error)[:300])
        print(run.dir.relative_to(ROOT))


if __name__ == "__main__":
    main()
