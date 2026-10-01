#!/usr/bin/env bash
# Generate RSA key pairs for the Snowflake service users (key-pair auth, no passwords).
#
#   secrets/snowflake/<user>/rsa_key.p8   private key (PKCS#8, encrypted unless noted)
#   secrets/snowflake/<user>/rsa_key.pub  public key (registered in Snowflake by Terraform/bootstrap)
#
# Passphrases are appended to .env (gitignored). Existing keys are never overwritten,
# so the script is safe to re-run. Usage: scripts/generate_keys.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="$ROOT/secrets/snowflake"
ENV_FILE="$ROOT/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

# user-dir : passphrase env var ("" = unencrypted; Grafana's plugin can't read encrypted keys,
# so the read-only BI user gets an unencrypted key)
KEYS=(
  "svc_terraform:SNOWFLAKE_TERRAFORM_KEY_PASSPHRASE"
  "svc_etl:SNOWFLAKE_ETL_KEY_PASSPHRASE"
  "svc_dbt:SNOWFLAKE_DBT_KEY_PASSPHRASE"
  "svc_bi:"
)

for entry in "${KEYS[@]}"; do
  name="${entry%%:*}"
  var="${entry#*:}"
  dir="$SECRETS/$name"
  if [[ -f "$dir/rsa_key.p8" ]]; then
    echo "skip  $name (key exists)"
    continue
  fi
  mkdir -p "$dir"
  chmod 700 "$dir"
  if [[ -n "$var" ]]; then
    pass="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)"
    openssl genrsa 2048 2>/dev/null \
      | openssl pkcs8 -topk8 -v2 aes-256-cbc -inform PEM -out "$dir/rsa_key.p8" -passout "pass:$pass"
    openssl rsa -in "$dir/rsa_key.p8" -passin "pass:$pass" -pubout -out "$dir/rsa_key.pub" 2>/dev/null
    grep -q "^$var=" "$ENV_FILE" || echo "$var=$pass" >> "$ENV_FILE"
  else
    openssl genrsa 2048 2>/dev/null \
      | openssl pkcs8 -topk8 -inform PEM -nocrypt -out "$dir/rsa_key.p8"
    openssl rsa -in "$dir/rsa_key.p8" -pubout -out "$dir/rsa_key.pub" 2>/dev/null
  fi
  chmod 600 "$dir/rsa_key.p8"
  echo "made  $name"
done

# Grafana's Snowflake plugin wants the BI key as a single base64url line (its UI normally does this
# conversion; file provisioning bypasses the UI). Derived from svc_bi, regenerated every run.
BI="$SECRETS/svc_bi"
if [[ -f "$BI/rsa_key.p8" ]]; then
  grep -v -- '-----' "$BI/rsa_key.p8" | tr -d '\n\r ' | tr '+/' '-_' > "$BI/rsa_key.grafana"
  chmod 600 "$BI/rsa_key.grafana"
  echo "made  svc_bi/rsa_key.grafana (base64url for Grafana)"
fi
