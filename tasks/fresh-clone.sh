#!/bin/bash
#MISE description="Bootstrap a fresh clone/devpod: pull secrets from Key Vault, then fetch talosconfigs"
set -euo pipefail

mise run bootstrap-env
echo ""
mise run gather-configs

echo ""
echo "▶ Bootstrap done: secrets pulled from Key Vault and talosconfigs fetched."
echo "   Verify with:  mise run validate"
