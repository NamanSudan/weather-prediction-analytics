#!/usr/bin/env bash
# Render the one-time bootstrap SQL with the Terraform service user's public key.
# Output is gitignored (it is account-specific); paste it into a Snowsight worksheet.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/secrets/snowflake/svc_terraform/rsa_key.pub"
TPL="$ROOT/infra/snowflake/bootstrap/00_bootstrap.sql.tpl"
OUT="$ROOT/infra/snowflake/bootstrap/00_bootstrap.rendered.sql"

[[ -f "$PUB" ]] || { echo "missing $PUB - run scripts/generate_keys.sh first" >&2; exit 1; }
KEY="$(grep -v -- '-----' "$PUB" | tr -d '\n')"
sed "s|{{TERRAFORM_PUBLIC_KEY}}|$KEY|" "$TPL" > "$OUT"
echo "wrote $OUT"
