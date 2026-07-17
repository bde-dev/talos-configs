#!/bin/bash
#MISE description="Rebuild ~/.talos/config from Omni: fetch each cluster's talosconfig and populate its default nodes"
set -euo pipefail

TALOSCONFIG="${TALOSCONFIG:-$HOME/.talos/config}"

# Preserve the currently-selected context so we can restore it at the end
orig_context=""
if [ -f "$TALOSCONFIG" ]; then
  orig_context=$(yq '.context' "$TALOSCONFIG")
  [ "$orig_context" = "null" ] && orig_context=""
fi

# Build into a throwaway dir, then swap in — avoids talosctl's rename-on-collision
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fresh="$tmpdir/config"

for dir in clusters/*/; do
  cluster=$(basename "$dir")
  echo ""
  echo "═══ $cluster ═══"

  # 1. Fetch this cluster's talosconfig standalone (Omni bakes the endpoint in)
  per="$tmpdir/$cluster.talosconfig"
  omnictl talosconfig "$per" -c "$cluster" --merge=false -f
  echo "✓ fetched"

  # 2. Accumulate — distinct cluster names never collide, so no -N rename
  if [ -f "$fresh" ]; then
    talosctl --talosconfig "$fresh" config merge "$per"
  else
    cp "$per" "$fresh"
  fi

  # 3. Resolve the context name (Omni names it <instance>-<cluster>)
  context=$(cluster="$cluster" yq '.contexts | keys | .[] | select(test("-" + strenv(cluster) + "$"))' "$fresh")
  [ "$context" = "null" ] && context=""
  if [ -z "$context" ]; then
    echo "⚠ no context matching *-$cluster — skipping node population"
    continue
  fi

  # 4. Pull node IPs from Omni and set them as this context's defaults
  mapfile -t nodes < <(
    omnictl get clustermachineidentity -l "omni.sidero.dev/cluster=$cluster" -o yaml 2>/dev/null \
      | grep -v '^\[WARN\]' \
      | yq '.spec.nodeips[]'
  )
  if [ "${#nodes[@]}" -eq 0 ]; then
    echo "⚠ no node IPs returned for $cluster — leaving nodes unset"
    continue
  fi
  talosctl --talosconfig "$fresh" config context "$context" >/dev/null
  talosctl --talosconfig "$fresh" config node "${nodes[@]}"
  echo "✓ $context → ${nodes[*]}"
done

# 5. Swap the freshly built config into place, restore prior selection
mkdir -p "$(dirname "$TALOSCONFIG")"
mv "$fresh" "$TALOSCONFIG"
[ -n "$orig_context" ] && talosctl config context "$orig_context" >/dev/null 2>&1 || true

echo ""
echo "✅ Done. talosctl contexts:"
talosctl config contexts
