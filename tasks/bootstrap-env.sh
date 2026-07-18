#!/bin/bash
#MISE description="Ensure .env exists with every required key (empty if unset)"
set -euo pipefail

ENV_FILE=".env"
KEYS=(CLIENT_ID CLIENT_SECRET SOPS_AGE_KEY OMNI_ENDPOINT OMNI_SERVICE_ACCOUNT_KEY)

[ -f "$ENV_FILE" ] || : > "$ENV_FILE"

added=0
for key in "${KEYS[@]}"; do
  grep -q "^${key}=" "$ENV_FILE" || { printf '%s=\n' "$key" >> "$ENV_FILE"; added=$((added + 1)); }
done

echo "✓ .env has all ${#KEYS[@]} required keys ($added added this run)"
echo "  CLIENT_ID + CLIENT_SECRET are yours to fill (Azure SP — from the homelab azure-creds secret)."
echo "  SOPS_AGE_KEY, OMNI_ENDPOINT, OMNI_SERVICE_ACCOUNT_KEY are populated by:  mise run pull-secrets"
