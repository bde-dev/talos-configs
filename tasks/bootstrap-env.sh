#!/bin/bash
#MISE description="Log in to Azure (service principal) and pull Omni + SOPS secrets from Key Vault into .env"
set -euo pipefail

: "${AZURE_TENANT_ID:?set in mise.toml [env]}"
: "${AKV_VAULT_NAME:?set in mise.toml [env]}"
: "${CLIENT_ID:?set CLIENT_ID in .env (Azure service-principal app id)}"
: "${CLIENT_SECRET:?paste your service-principal secret into .env}"

ENV_FILE=".env"

echo "Logging in to Azure with the service principal..."
az login --service-principal \
  --username "$CLIENT_ID" \
  --password "$CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --output none
echo "✓ az authenticated"

# Upsert KEY=VALUE into .env without disturbing other lines
upsert() {
  local key=$1 val=$2
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    grep -v "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  fi
  printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
}

# Key Vault secret name -> .env variable
pull() {
  local kv_name=$1 env_var=$2 val
  val=$(az keyvault secret show --vault-name "$AKV_VAULT_NAME" --name "$kv_name" --query value -o tsv)
  upsert "$env_var" "$val"
  echo "✓ $env_var  ← $kv_name"
}

pull sops-age-key             SOPS_AGE_KEY
pull omni-endpoint            OMNI_ENDPOINT
pull omni-service-account-key OMNI_SERVICE_ACCOUNT_KEY

echo ""
echo "✅ Pulled 3 secrets from Key Vault '$AKV_VAULT_NAME' into $ENV_FILE."
echo "   omnictl + sops are now authenticated — try:  mise run validate"
