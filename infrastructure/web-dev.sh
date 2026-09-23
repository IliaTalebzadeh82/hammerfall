#!/bin/sh
set -eu

# Named volumes persist dependencies; reinstall only when either manifest changes.
if ! sha256sum --check --status node_modules/.hammerfall-dependencies 2>/dev/null; then
  npm ci
  sha256sum package.json package-lock.json > node_modules/.hammerfall-dependencies
fi

exec npm run dev -- --hostname 0.0.0.0
