#!/usr/bin/env bash
# Populate .env with generated runtime secrets for the Docker stack (idempotent: never
# overwrites a value that is already set). Non-secret settings come from .env.example.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

rand() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-"${1:-32}"; }
set_default() {  # key value
  grep -q "^$1=" "$ENV_FILE" || echo "$1=$2" >> "$ENV_FILE"
}

# non-secret defaults (copied from .env.example on first run)
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  set_default "${line%%=*}" "${line#*=}"
done < "$ROOT/.env.example"

# generated secrets
set_default AIRFLOW_UID "$(id -u)"
set_default AIRFLOW_FERNET_KEY "$(openssl rand -base64 32 | tr '+/' '-_')"
set_default AIRFLOW_JWT_SECRET "$(rand 48)"
set_default AIRFLOW_ADMIN_PASSWORD "$(rand 20)"
set_default POSTGRES_PASSWORD "$(rand 24)"
set_default SUPERSET_SECRET_KEY "$(rand 48)"
set_default SUPERSET_ADMIN_PASSWORD "$(rand 20)"
set_default GRAFANA_ADMIN_PASSWORD "$(rand 20)"

echo "ok: $ENV_FILE has $(grep -c '=' "$ENV_FILE") keys (values not shown)"
