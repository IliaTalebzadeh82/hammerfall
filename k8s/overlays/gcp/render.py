#!/usr/bin/env python3
"""Materialize the static GKE overlay after explicit deployment inputs exist."""

import argparse
import re
import subprocess
from pathlib import Path


def require(pattern, value, label):
    if not re.fullmatch(pattern, value):
        raise SystemExit(f"invalid {label}")
    return value


parser = argparse.ArgumentParser()
parser.add_argument("--project-id", required=True)
parser.add_argument("--hostname", required=True)
parser.add_argument("--certificate-map", required=True)
parser.add_argument("--static-ip-name", required=True)
parser.add_argument("--redis-host", required=True)
parser.add_argument("--kafka-bootstrap-address", required=True)
parser.add_argument("--api-digest", required=True)
parser.add_argument("--web-digest", required=True)
parser.add_argument("--kafka-auth-digest", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

project = require(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", args.project_id, "project ID")
hostname = require(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])", args.hostname, "hostname")
if "." not in hostname or hostname.endswith(".invalid"):
    raise SystemExit("hostname must be a real fully qualified domain name")
certmap = require(r"[a-z][a-z0-9-]{0,62}", args.certificate_map, "certificate map")
ip_name = require(r"[a-z][a-z0-9-]{0,62}", args.static_ip_name, "static IP name")
redis = require(r"[a-zA-Z0-9.-]+", args.redis_host, "Redis host")
kafka = require(r"[a-zA-Z0-9.-]+:[0-9]{2,5}", args.kafka_bootstrap_address, "Kafka bootstrap address")
digest = r"[0-9a-f]{64}"
api_digest = require(digest, args.api_digest, "API digest")
web_digest = require(digest, args.web_digest, "web digest")
auth_digest = require(digest, args.kafka_auth_digest, "Kafka auth digest")
if any(value in {"1" * 64, "2" * 64, "3" * 64} for value in (api_digest, web_digest, auth_digest)):
    raise SystemExit("placeholder image digest is not deployable")

overlay = Path(__file__).resolve().parent
rendered = subprocess.check_output(["kubectl", "kustomize", str(overlay)], text=True)
replacements = {
    "PROJECT_ID": project,
    "PUBLIC_HOSTNAME.invalid": hostname,
    "CERT_MAP_NAME": certmap,
    "STATIC_IP_NAME": ip_name,
    "REDIS_HOST": redis,
    "KAFKA_BOOTSTRAP_ADDRESS": kafka,
    "sha256:" + "1" * 64: "sha256:" + api_digest,
    "sha256:" + "2" * 64: "sha256:" + web_digest,
    "sha256:" + "3" * 64: "sha256:" + auth_digest,
}
for old, new in replacements.items():
    if old not in rendered:
        raise SystemExit(f"overlay placeholder missing: {old}")
    rendered = rendered.replace(old, new)

Path(args.output).write_text(rendered)
