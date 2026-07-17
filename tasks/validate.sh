#!/bin/bash
#MISE description="Validate all cluster templates (decrypts SOPS secrets first)"
set -euo pipefail

# Decrypt SOPS files in-place (temporarily)
DECRYPTED=()
for f in $(find . -path './.sops.yaml' -prune -o -name '*.sops.yaml' -print); do
  if sops -d -i "$f" 2>/dev/null; then
    DECRYPTED+=("$f")
    echo "✓ Decrypted $f"
  else
    echo "⚠ Could not decrypt $f (missing key?) — skipping"
  fi
done

# Restore encrypted files on exit
cleanup() {
  for f in "${DECRYPTED[@]}"; do
    git checkout -- "$f" 2>/dev/null && echo "✓ Restored $f"
  done
}
trap cleanup EXIT

# Validate each cluster
ERRORS=0
for dir in clusters/*/; do
  cluster=$(basename "$dir")
  echo ""
  echo "═══ Validating $cluster ═══"
  if (cd "$dir" && omnictl cluster template validate -f template.yaml --allowed-dir ../..); then
    echo "✅ $cluster is valid"
  else
    echo "❌ $cluster has errors"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "❌ $ERRORS cluster(s) failed validation"
  exit 1
else
  echo "✅ All clusters valid"
fi
