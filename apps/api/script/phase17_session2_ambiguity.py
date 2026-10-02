"""Local Compose-only cross-replica command crash proof. Run from repo root."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[3]
API = "http://127.0.0.1:3001"


def docker(*args):
    return subprocess.run(["docker", "compose", *args], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout.strip()


def request(method, path, payload=None, key=None):
    headers = {"Connection": "close"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if key:
        headers["Idempotency-Key"] = key
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, dict(response.headers), json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), json.load(error) if error.headers.get("Content-Type", "").startswith("application/json") else None
    except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
        return None, {}, type(error).__name__


def ok(method, path, payload=None, key=None, status=200):
    result = request(method, path, payload, key)
    assert result[0] == status, (method, path, result)
    return result


def snapshot(auction_id, actor_id, key):
    digest = hashlib.sha256(key.encode()).hexdigest()
    ruby = (
        "require 'json'; a=Auction.find(%d); "
        "puts JSON.generate(auction: a.attributes.slice('status','current_price','current_leader_id','public_revision','ends_at','original_ends_at','winner_id','closed_at'), "
        "bids: a.bids.order(:sequence).pluck(:id,:sequence,:amount,:bidder_id), "
        "maximum_bids: a.maximum_bids.order(:priority_sequence).pluck(:id,:priority_sequence,:maximum_amount), "
        "outbox_count: OutboxEvent.where(auction_id:a.id).count, "
        "command: IdempotencyRecord.where(actor_id:%d,operation:'place_bid',key_digest:'%s').pluck(:status,:response_status,:response_body))"
    ) % (auction_id, actor_id, digest)
    return json.loads(docker("exec", "-T", "auction-closer", "bin/rails", "runner", ruby).splitlines()[-1])


def healthy(service, deadline=60):
    end = time.monotonic() + deadline
    while time.monotonic() < end:
        cid = docker("ps", "-q", service)
        if cid:
            state = subprocess.run(["docker", "inspect", "-f", "{{.State.Health.Status}}", cid], capture_output=True, text=True)
            if state.stdout.strip() == "healthy":
                return
        time.sleep(0.5)
    raise AssertionError(f"{service} did not become healthy")


def fixture(label):
    actor = ok("POST", "/api/v1/users", {"user": {"name": f"P17 S2 {label} {uuid.uuid4().hex[:8]}"}}, status=201)[2]["data"]["id"]
    now = time.time()
    from datetime import datetime, timezone, timedelta
    start = datetime.fromtimestamp(now - 60, timezone.utc).isoformat()
    end = datetime.fromtimestamp(now + 3600, timezone.utc).isoformat()
    aid = ok("POST", "/api/v1/auctions", {"auction": {"title": f"P17 S2 {label} {uuid.uuid4().hex[:8]}",
        "starting_price": 10000, "minimum_increment": 1000, "starts_at": start, "ends_at": end}}, status=201)[2]["data"]["id"]
    path = f"/api/v1/auctions/{aid}"
    ok("POST", path + "/schedule")
    ok("POST", path + "/activate")
    return aid, actor, path


def run(boundary, override):
    aid, actor, path = fixture(boundary)
    key = str(uuid.uuid4())
    before = snapshot(aid, actor, key)
    override.write_text("services:\n  api-replica-b:\n    environment:\n"
        f"      HAMMERFALL_CHAOS_CONFIRM: phase-16-local-crash\n      HAMMERFALL_CHAOS_CRASH_BOUNDARY: {boundary}\n      HAMMERFALL_CHAOS_AUCTION_ID: '{aid}'\n")
    docker("-f", "docker-compose.yml", "-f", str(override), "up", "-d", "--no-deps", "--force-recreate", "api-replica-b")
    healthy("api-replica-b")
    docker("up", "-d", "--no-deps", "--force-recreate", "api-proxy")
    healthy("api-proxy")
    docker("stop", "api")
    try:
        first = request("POST", path + "/bids", {"bid": {"bidder_id": actor, "amount": 10000}}, key)
        assert first[0] != 201, f"crash request unexpectedly succeeded: {first}"
        logs = docker("logs", "--tail", "50", "api-replica-b")
        assert f"chaos_crash boundary={boundary} auction_id={aid}" in logs, logs[-1500:]
        crashed = snapshot(aid, actor, key)
    finally:
        docker("start", "api")
        healthy("api")
    retry = ok("POST", path + "/bids", {"bid": {"bidder_id": actor, "amount": 10000}}, key, status=201)
    response_headers = {name.lower(): value for name, value in retry[1].items()}
    assert response_headers.get("x-hammerfall-instance") == "a", retry[1]
    after = snapshot(aid, actor, key)
    assert after["auction"]["public_revision"] == before["auction"]["public_revision"] + 1
    assert after["outbox_count"] == before["outbox_count"] + 1
    assert len(after["bids"]) == len(before["bids"]) + 1
    assert len(after["command"]) == 1
    if boundary == "command_committed":
        assert response_headers.get("idempotency-replayed") == "true"
        assert crashed == after, (crashed, after)
    else:
        assert response_headers.get("idempotency-replayed") is None
        assert crashed == before, (crashed, before)
    print(json.dumps({"scenario": boundary, "auction_id": aid, "first_status": first[0],
        "crash_instance": "b", "retry_instance": "a", "replayed": boundary == "command_committed",
        "before": before, "after_crash": crashed, "after_retry": after}), flush=True)


with tempfile.TemporaryDirectory(prefix="phase17-fault-") as temp:
    override = Path(temp) / "override.yml"
    try:
        for boundary in ("command_committed", "command_before_commit"):
            run(boundary, override)
            docker("up", "-d", "--no-deps", "--force-recreate", "api-replica-b")
            healthy("api-replica-b")
            docker("up", "-d", "--no-deps", "--force-recreate", "api-proxy")
            healthy("api-proxy")
    finally:
        docker("start", "api")
        docker("up", "-d", "--no-deps", "--force-recreate", "api-replica-b")
        docker("up", "-d", "--no-deps", "--force-recreate", "api-proxy")
