#!/usr/bin/env python3
"""Wait for the independent closer after a closing-storm measurement."""
import argparse
import datetime as dt
import json
import pathlib
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    fixture = json.loads(args.manifest.read_text())
    url = fixture["api_base_url"] + "/api/v1/auctions/" + str(fixture["auctions"][0])
    deadline = time.monotonic() + args.timeout
    observations = []
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                auction = json.load(response)["data"]
            observations.append({"at": dt.datetime.now(dt.timezone.utc).isoformat(),
                                 "status": auction["status"], "ends_at": auction["ends_at"]})
            if auction["status"] == "closed":
                break
        except (OSError, ValueError) as error:
            observations.append({"at": dt.datetime.now(dt.timezone.utc).isoformat(),
                                 "error": type(error).__name__})
        time.sleep(1)
    args.output.write_text(json.dumps(observations, indent=2) + "\n")
    if not observations or observations[-1].get("status") != "closed":
        raise SystemExit("auction did not close within observation window")
    print(json.dumps({"observations": len(observations), "closed": observations[-1]}))


if __name__ == "__main__":
    main()
