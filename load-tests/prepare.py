#!/usr/bin/env python3
"""Create isolated, reproducible HTTP fixtures for one benchmark run."""
import argparse
import datetime as dt
import json
import pathlib
import urllib.error
import urllib.request
import uuid


def request(base, method, path, body=None):
    payload = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=payload, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)["data"]
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{method} {path}: {error.code} {error.read().decode()}") from error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:3001")
    parser.add_argument("--scenario", choices=["normal", "hot", "distributed", "duplicate", "burst", "closing", "challenge", "fanout"], required=True)
    parser.add_argument("--auctions", type=int, default=1)
    parser.add_argument("--users", type=int, default=24)
    parser.add_argument("--minutes", type=int, default=15)
    parser.add_argument("--seconds", type=int, help="Deadline offset after auction creation (closing/challenge only)")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    if min(args.auctions, args.users, args.minutes) < 1:
        parser.error("auctions, users and minutes must be positive")
    if args.seconds is not None and (args.scenario not in ("closing", "challenge") or args.seconds < 5):
        parser.error("--seconds requires closing/challenge and at least 5 seconds")
    base = args.base_url.rstrip("/")
    with urllib.request.urlopen(base + "/up", timeout=5) as response:
        if response.status != 200:
            raise RuntimeError("API health check failed")
    run_id = f"p14-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"
    users = [request(base, "POST", "/api/v1/users", {"user": {"name": f"{run_id}-bidder-{i:04d}"}})["id"]
             for i in range(args.users)]
    now = dt.datetime.now(dt.timezone.utc)
    starts_at = (now - dt.timedelta(minutes=2)).isoformat().replace("+00:00", "Z")
    ends_at = (now + dt.timedelta(seconds=args.seconds) if args.seconds is not None
               else now + dt.timedelta(minutes=args.minutes)).isoformat().replace("+00:00", "Z")
    auctions = []
    for i in range(args.auctions):
        auction = request(base, "POST", "/api/v1/auctions", {"auction": {
            "title": f"{run_id}-auction-{i:04d}", "description": "Phase 14 isolated fixture",
            "starting_price": 10000, "minimum_increment": 100,
            "starts_at": starts_at, "ends_at": ends_at}})
        aid = auction["id"]
        request(base, "POST", f"/api/v1/auctions/{aid}/schedule")
        request(base, "POST", f"/api/v1/auctions/{aid}/activate")
        auctions.append(aid)
    manifest = {"run_id": run_id, "scenario": args.scenario, "api_base_url": base,
                "created_at": now.isoformat(), "starts_at": starts_at, "ends_at": ends_at,
                "starting_price": 10000, "minimum_increment": 100,
                "users": users, "auctions": auctions,
                "duplicate_key": f"{run_id}-duplicate-command"}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"manifest": str(args.output), "run_id": run_id,
                      "users": len(users), "auctions": auctions}))


if __name__ == "__main__":
    main()
