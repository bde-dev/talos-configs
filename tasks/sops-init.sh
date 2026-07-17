#!/bin/bash
#MISE description="Scaffold .env for the SOPS age key, then verify it decrypts this repo's secrets"
set -euo pipefail

ENV_FILE=".env"
SOPS_FILE=".sops.yaml"

# The public key (recipient) this repo encrypts its secrets to
recipient=$(yq '.creation_rules[0].age' "$SOPS_FILE" | tr -d '[:space:]')

# If mise already loaded a key from .env, verify it matches the recipient
if [ -n "${SOPS_AGE_KEY:-}" ]; then
  derived=$(printf '%s\n' "$SOPS_AGE_KEY" | age-keygen -y - 2>/dev/null || true)
  if [ "$derived" = "$recipient" ]; then
    echo "✅ SOPS_AGE_KEY is set and derives to this repo's recipient:"
    echo "     $recipient"
    echo "   sops can decrypt — run:  mise run validate"
    exit 0
  fi
  echo "❌ SOPS_AGE_KEY is set but its public key does NOT match .sops.yaml"
  echo "     expected: $recipient"
  echo "     got:      ${derived:-<could not derive — malformed key?>}"
  echo "   Re-paste the 'AGE Secret Key' (from Bitwarden) into $ENV_FILE and re-run."
  exit 1
fi

# No key loaded yet — make a place to paste it
[ -f "$ENV_FILE" ] || : > "$ENV_FILE"
grep -q '^SOPS_AGE_KEY=' "$ENV_FILE" || printf 'SOPS_AGE_KEY=\n' >> "$ENV_FILE"

echo "📋 Next steps to enable secret decryption:"
echo "   1. In Bitwarden, copy the 'AGE Secret Key' — the AGE-SECRET-KEY-... value, NOT the 'Public Key' (age1...)."
echo "   2. Paste it into $ENV_FILE after 'SOPS_AGE_KEY='   ($ENV_FILE is gitignored)."
echo "   3. Verify:   mise run sops-init     (checks it derives to the recipient below)"
echo "   4. Decrypt:  mise run validate"
echo ""
echo "   Repo recipient (the 'Public Key' your secret key must derive to):"
echo "     $recipient"
