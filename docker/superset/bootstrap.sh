#!/usr/bin/env bash
# One-shot Superset setup (idempotent): metadata DB, schema migrations, admin user, roles.
set -euo pipefail

/app/.venv/bin/python - <<'PY'
import os, psycopg2
conn = psycopg2.connect(host="postgres", dbname="airflow", user="airflow", password=os.environ["POSTGRES_PASSWORD"])
conn.autocommit = True
cur = conn.cursor()
cur.execute("SELECT 1 FROM pg_database WHERE datname = 'superset'")
if not cur.fetchone():
    cur.execute("CREATE DATABASE superset")
    print("created metadata database 'superset'")
PY

superset db upgrade
superset fab create-admin --username "$SUPERSET_ADMIN_USER" --firstname Lab --lastname Admin \
  --email admin@lab1.local --password "$SUPERSET_ADMIN_PASSWORD" || true
superset init
echo "superset bootstrap complete"
