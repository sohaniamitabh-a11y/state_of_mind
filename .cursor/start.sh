#!/usr/bin/env bash
# Per-boot startup: make sure the local MySQL daemon is running and ready.
set -euo pipefail

sudo service mysql start || true
for _ in $(seq 1 30); do
  if sudo mysqladmin ping >/dev/null 2>&1; then
    echo "[start] MySQL is up."
    exit 0
  fi
  sleep 1
done

echo "[start] MySQL did not become ready in time." >&2
exit 1
