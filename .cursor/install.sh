#!/usr/bin/env bash
# Idempotent local-development bootstrap for State of Mind.
#
# Sets up a local MySQL server (standing in for the cloud Aiven DB),
# a Python virtualenv, the project's Python dependencies, and seeds the
# database with schema + mood/genre data. Safe to run repeatedly.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DB_NAME="state_of_mind"
DB_USER="som_user"
DB_PASSWORD="som_local_pw"
DB_HOST="127.0.0.1"
DB_PORT="3306"
CERT_DIR="$HOME/.mysql-local-certs"
CA_PATH="$CERT_DIR/ca.pem"

echo "[install] Ensuring MySQL server is installed..."
if ! command -v mysqld >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
fi

echo "[install] Ensuring Python venv tooling is installed..."
if ! dpkg -s python3-venv >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-venv python3-pip
fi

echo "[install] Starting MySQL service..."
sudo service mysql start || true
# Wait for the server to accept connections.
for _ in $(seq 1 30); do
  if sudo mysqladmin ping >/dev/null 2>&1; then break; fi
  sleep 1
done

echo "[install] Creating database and application user..."
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "[install] Exposing the local MySQL CA certificate for SSL connections..."
mkdir -p "$CERT_DIR"
sudo cp /var/lib/mysql/ca.pem "$CA_PATH"
sudo chown "$(id -u):$(id -g)" "$CA_PATH"

echo "[install] Writing .env (local dev defaults) if missing..."
if [ ! -f "$REPO_ROOT/.env" ]; then
  cat > "$REPO_ROOT/.env" <<ENV
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSL_CA=${CA_PATH}
ENV
fi

echo "[install] Creating Python virtualenv and installing dependencies..."
if [ ! -d "$REPO_ROOT/.venv" ]; then
  python3 -m venv "$REPO_ROOT/.venv"
fi
# shellcheck disable=SC1091
source "$REPO_ROOT/.venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$REPO_ROOT/requirements.txt"

echo "[install] Applying schema (idempotent)..."
python3 run_schema.py

# The seed scripts are NOT safe to re-run: music genres carry a NULL
# external_id, and MySQL's UNIQUE(media_type, external_id) treats NULLs as
# distinct, so re-seeding would insert duplicate genre rows. Guard the seed
# step on whether the "brain" table has already been populated.
ALREADY_SEEDED="$(python3 - <<'PY'
import os
from dotenv import load_dotenv
import mysql.connector
load_dotenv(".env")
conn = mysql.connector.connect(
    host=os.getenv("DB_HOST"), port=int(os.getenv("DB_PORT")),
    user=os.getenv("DB_USER"), password=os.getenv("DB_PASSWORD"),
    database=os.getenv("DB_NAME"), ssl_ca=os.getenv("DB_SSL_CA"), ssl_verify_cert=True)
cur = conn.cursor()
cur.execute("SELECT COUNT(*) FROM mood_genre_mapping")
print("yes" if cur.fetchone()[0] > 0 else "no")
conn.close()
PY
)"

if [ "$ALREADY_SEEDED" = "no" ]; then
  echo "[install] Seeding moods, genres, and mood-genre mappings..."
  python3 run_seed.py
  python3 run_expand_genres.py
  python3 run_mapping.py
else
  echo "[install] Seed data already present — skipping seed scripts."
fi

echo "[install] Harvesting sample music items from Deezer (best-effort)..."
# The Deezer public chart endpoint needs no API key. Network hiccups here
# should not fail environment setup, so this step is best-effort.
python3 harvest_music.py || echo "[install] Music harvest skipped (network unavailable)."

echo "[install] Done. Activate with 'source .venv/bin/activate' and run 'python3 app.py'."
