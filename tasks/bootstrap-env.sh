#!/bin/bash
#MISE description="Ensure .env holds each required key that isn't already provided (via .env or the shell env)"
set -euo pipefail

ENV_FILE=".env"
# CLIENT_ID is non-secret and lives in mise.toml [env]. CLIENT_SECRET may be
# provided by a shell export or a .env line. These are the keys .env may hold.
KEYS=(CLIENT_SECRET SOPS_AGE_KEY OMNI_ENDPOINT OMNI_SERVICE_ACCOUNT_KEY)

[ -f "$ENV_FILE" ] || : > "$ENV_FILE"

added=0
for key in "${KEYS[@]}"; do
  grep -q "^${key}=" "$ENV_FILE" && continue                    # already a line in .env
  [ -n "$(printenv "$key" 2>/dev/null || true)" ] && continue   # already set in the shell env
  printf '%s=\n' "$key" >> "$ENV_FILE"
  added=$((added + 1))
done

echo "✓ .env ready ($added empty key(s) added; existing and shell-provided keys left untouched)"
echo "  CLIENT_SECRET is the only value you supply — export it, or fill it in .env."
echo "  SOPS_AGE_KEY, OMNI_ENDPOINT, OMNI_SERVICE_ACCOUNT_KEY are filled by:  mise run pull-secrets"
