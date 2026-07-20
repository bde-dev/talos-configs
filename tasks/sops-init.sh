#!/bin/bash
#MISE description="Verify the SOPS age key in .env decrypts this repo's secrets"
set -euo pipefail

SOPS_FILE=".sops.yaml"

# The public key (recipient) this repo encrypts its secrets to
recipient=$(yq '.creation_rules[0].age' "$SOPS_FILE" | tr -d '[:space:]')

if [ -z "${SOPS_AGE_KEY:-}" ]; then
  echo "SOPS_AGE_KEY is empty in .env."
  echo "  Populate it with:  mise run pull-secrets   (pulls it from Key Vault)"
  echo "  or paste the AGE Secret Key (AGE-SECRET-KEY-..., not the public key) into .env."
  echo "  It must derive to this repo's recipient: $recipient"
  exit 1
fi

derived=$(printf '%s\n' "$SOPS_AGE_KEY" | age-keygen -y - 2>/dev/null || true)
if [ "$derived" = "$recipient" ]; then
  echo "✅ SOPS_AGE_KEY derives to this repo's recipient:"
  echo "     $recipient"
  echo "   sops can decrypt — run:  mise run validate"
  exit 0
fi

echo "❌ SOPS_AGE_KEY is set but does NOT match .sops.yaml"
echo "     expected: $recipient"
echo "     got:      ${derived:-<could not derive — malformed key?>}"
exit 1
