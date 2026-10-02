#!/usr/bin/env python3
"""Deterministic Phase 16 post-effect crash campaigns; run from repo root."""
import argparse
import subprocess
import time

from run import Run, ROOT, compose, now, require


def crash(run, service, boundary, event_id, ruby):
    # A one-off Rails process in the running API container has no restart policy;
    # its injected death cannot silently restart and acknowledge the row.
    args = ["docker", "compose", "exec", "-T",
            "-e", "KAFKA_BOOTSTRAP_SERVERS=kafka:9092",
            "-e", "HAMMERFALL_CHAOS_CONFIRM=phase-16-local-crash",
            "-e", f"HAMMERFALL_CHAOS_CRASH_BOUNDARY={boundary}",
            "-e", f"HAMMERFALL_CHAOS_EVENT_ID={event_id}",
            "api", "bin/rails", "runner", ruby]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=65)
    output = result.stdout + result.stderr
    (run.dir / "crash.log").write_text(output[-3000:])
    run.record("injected_process_exited", service=service, boundary=boundary,
               event_id=event_id, exit_code=result.returncode)
    require(result.returncode in (137, -9) and
            f"chaos_crash boundary={boundary} event_id={event_id}" in output,
            f"target process did not die at {boundary}; exit={result.returncode}")


def event_state(run, event_id):
    return next(row for row in run.probe()["event_delivery"] if row["event_id"] == event_id)


def wait_probe(run, label, predicate, timeout=120):
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        state = run.probe()
        if predicate(state):
            run.record(label, elapsed_seconds=round(time.monotonic() - start, 2))
            return state
        time.sleep(5)
    raise TimeoutError(f"{label} did not become true within {timeout} seconds")


def offsets(run, stage):
    result = subprocess.run(["docker", "compose", "exec", "-T", "kafka",
        "/opt/kafka/bin/kafka-consumer-groups.sh", "--bootstrap-server", "kafka:9092",
        "--describe", "--group", "hammerfall.audit.v1"], cwd=ROOT,
        capture_output=True, text=True, timeout=30)
    require(result.returncode == 0, f"offset query failed at {stage}")
    (run.dir / f"offsets-{stage}.txt").write_text(result.stdout)
    run.record("offsets_captured", stage=stage)
    return result.stdout


def publisher(run):
    run.fixture(); run.bid()
    run.wait("baseline", run.converged)
    run.stop("kafka-outbox-publisher")
    run.bid()
    before = run.snapshot("before_crash")
    event_id = before["postgresql"]["latest_event_id"]
    expected = event_state(run, event_id)
    require(not expected["kafka_acknowledged"], "target event already acknowledged")
    since = now()
    crash(run, "kafka-outbox-publisher", "kafka_delivered", event_id,
          "KafkaOutboxPublisher.new.run(once: true)")
    after = run.snapshot("after_crash")
    observed = event_state(run, event_id)
    require(not observed["kafka_acknowledged"] and observed["kafka_attempts"] == 0,
            "SQL acknowledgment committed despite crash")
    require(observed["payload_sha256"] == expected["payload_sha256"],
            "outbox payload changed at crash")
    require(after["postgresql"]["bid_count"] == before["postgresql"]["bid_count"],
            "auction state changed during publication")
    wait_probe(run, "first_audit_effect", lambda s: next(
        row for row in s["event_delivery"] if row["event_id"] == event_id)["audit_effects"] == 1)
    run.start("kafka-outbox-publisher")
    run.wait_log_result("kafka-audit-consumer", event_id, "duplicate", since)
    run.wait_log_result("kafka-projection-consumer", event_id, "duplicate", since)
    recovered = run.wait("recovered", run.converged)
    final_event = event_state(run, event_id)
    require(final_event["kafka_acknowledged"] and final_event["kafka_attempts"] == 1 and
            final_event["payload_sha256"] == expected["payload_sha256"] and
            final_event["audit_receipts"] == final_event["audit_effects"] == 1,
            "publisher recovery violated event identity or duplicate-effect bound")
    require(recovered["postgresql"]["bid_count"] == before["postgresql"]["bid_count"],
            "publication retry changed auction state")


def consumer(run):
    run.fixture(); run.bid()
    run.wait("baseline", run.converged)
    run.stop("kafka-audit-consumer")
    run.bid()
    before = run.snapshot("before_crash")
    event_id = before["postgresql"]["latest_event_id"]
    wait_probe(run, "broker_acknowledged", lambda s: next(
        row for row in s["event_delivery"] if row["event_id"] == event_id)["kafka_acknowledged"])
    expected = event_state(run, event_id)
    require(expected["audit_effects"] == 0, "target audit effect already recorded")
    offsets(run, "before")
    since = now()
    crash(run, "kafka-audit-consumer", "audit_effect_committed", event_id,
          "KafkaAuditConsumer.new.run")
    crashed = run.snapshot("after_crash")
    actual = event_state(run, event_id)
    require(actual["audit_receipts"] == actual["audit_effects"] == 1,
            "audit receipt/effect did not commit before death")
    offsets(run, "after_crash")
    require(crashed["postgresql"]["bid_count"] == before["postgresql"]["bid_count"],
            "consumer crash changed auction state")
    run.start("kafka-audit-consumer")
    run.wait_log_result("kafka-audit-consumer", event_id, "duplicate", since)
    run.wait("recovered", run.converged)
    offsets(run, "recovered")
    actual = event_state(run, event_id)
    require(actual["audit_receipts"] == actual["audit_effects"] == 1,
            "redelivery duplicated audit effect")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", choices=["publisher", "consumer"])
    args = parser.parse_args()
    run = Run("session2-" + args.scenario)
    try:
        {"publisher": publisher, "consumer": consumer}[args.scenario](run)
        run.verify()
        final = run.snapshot("final")
        require(run.converged(final), "final derived state did not converge")
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
