#!/bin/bash
#MISE description="Bootstrap a fresh clone/devpod: scaffold the SOPS key placeholder, then fetch talosconfigs"
set -euo pipefail

mise run sops-init
echo ""
mise run gather-configs

echo ""
echo "▶ Bootstrap done. One manual step remains:"
echo "   • Grab the SOPS age key from Bitwarden and paste it into .env (after SOPS_AGE_KEY=)."
echo "   • Then run:  mise run validate"
