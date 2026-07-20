#!/bin/bash
#MISE description="Full bootstrap: ensure .env keys, pull secrets, verify sops, validate, gather configs"
set -euo pipefail

mise run bootstrap-env
echo ""
mise run pull-secrets
echo ""
mise run sops-init
echo ""
mise run validate
echo ""
mise run gather-configs

echo ""
echo "▶ Fresh clone ready: .env scaffolded, secrets pulled, templates validated, talosconfigs fetched."
