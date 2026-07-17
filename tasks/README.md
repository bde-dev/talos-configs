# Tasks

[mise](https://mise.jdx.dev) tasks for this repo. `mise.toml` wires this directory in via `[task_config] includes = ["tasks"]`, so any executable script here with a `#MISE description="…"` header comment is a task. List them with `mise tasks`; run one with `mise run <name>`.

| Task | What it does |
|---|---|
| `fresh-clone` | Bootstrap a fresh clone/devpod: `bootstrap-env` + `gather-configs` |
| `bootstrap-env` | Pull Omni + SOPS secrets from Azure Key Vault into `.env` |
| `sops-init` | Fallback without Key Vault: scaffold `.env` for the SOPS age key and verify it |
| `validate` | Validate every cluster template against Omni (decrypts secrets first) |
| `gather-configs` | Build `~/.talos/config` from Omni with default node IPs |

## `fresh-clone` — `fresh-clone.sh`

Makes a freshly cloned repo or rebuilt devpod usable in one task: `bootstrap-env` (secrets → `.env`) then `gather-configs` (talosconfigs → `~/.talos/config`).

```bash
cp .env.example .env         # fill CLIENT_ID + CLIENT_SECRET
mise run fresh-clone
mise run validate
```

## `bootstrap-env` — `bootstrap-env.sh`

Secrets live in Azure Key Vault `bde-dev-kv-homelab`. This task logs in with the Azure service principal and pulls them into `.env`, so the only value pasted by hand is the SP client secret.

Tenant and vault are non-secret and set in `mise.toml [env]`; `CLIENT_ID` + `CLIENT_SECRET` come from `.env` (copy `.env.example`), and only `CLIENT_SECRET` is sensitive. Each Key Vault secret maps to a `.env` variable:

| Key Vault secret | `.env` variable |
|---|---|
| `sops-age-key` | `SOPS_AGE_KEY` |
| `omni-endpoint` | `OMNI_ENDPOINT` |
| `omni-service-account-key` | `OMNI_SERVICE_ACCOUNT_KEY` |

```bash
mise run bootstrap-env       # az login (service principal) → az keyvault secret show → .env
mise run validate
```

**Needs:** `azure-cli` (pinned in `mise.toml`) and `CLIENT_ID`/`CLIENT_SECRET` in `.env`. Idempotent — re-run to refresh.

## `sops-init` — `sops-init.sh`

The fallback for setups without Key Vault: it gives you a place to paste the SOPS **age private key** so `sops` (and `mise run validate`) can decrypt. `bootstrap-env` covers this when Key Vault is available.

- First run creates `.env` with an empty `SOPS_AGE_KEY=` line and prints the recipient the key must match.
- Paste the **AGE Secret Key** (the `AGE-SECRET-KEY-…` value, not the public key) after `SOPS_AGE_KEY=`.
- Re-run to verify: it derives the public key from what you pasted and checks it equals the `.sops.yaml` recipient.

```bash
mise run sops-init
# …paste the key into .env…
mise run sops-init           # verifies it matches the repo recipient
mise run validate
```

**Needs:** `age` (pinned in `mise.toml`). Idempotent.

## `validate` — `validate.sh`

The local mirror of CI. For each `clusters/*/`:

- Decrypts all `*.sops.yaml` in place, runs `omnictl cluster template validate -f template.yaml --allowed-dir ../..`, then restores the encrypted files via an `EXIT` trap, so plaintext never lingers even on failure.
- Exits non-zero if any cluster fails. Also enforced by `.githooks/pre-push`.

```bash
mise run validate
```

**Needs:** `SOPS_AGE_KEY` in `.env` (from `bootstrap-env` or `sops-init`). Without it, encrypted patches are skipped with a warning.

## `gather-configs` — `gather-configs.sh`

Builds `~/.talos/config` from Omni so `talosctl` reaches each cluster with no `--nodes` flag. For each `clusters/*/`:

1. Fetches the cluster's talosconfig standalone from Omni (`omnictl talosconfig --merge=false`); the Omni endpoint is baked in.
2. Accumulates them into a fresh config — distinct context names, so no `-N` rename collisions.
3. Reads the cluster's node IPs from Omni's `clustermachineidentity` resource (scoped by the `omni.sidero.dev/cluster` label) and sets them as the context's default nodes.
4. Swaps the built file into `~/.talos/config` and restores the previously-selected context.

```bash
mise run gather-configs
talosctl config contexts     # bde-dev-<cluster>, each with NODES populated
talosctl version             # hits the default node — no --nodes needed
```

`~/.talos/config` is a regenerable artefact of Omni: a rerun rebuilds it (dropping any stale `-N` contexts) and does not preserve hand-added non-Omni contexts.

**Needs:** authenticated `omnictl` — `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` in `.env` (from `bootstrap-env`), or the `omniconfig.yaml` interactive login.

## Adding a task

Drop an executable script here with a MISE header comment:

```bash
#!/bin/bash
#MISE description="what it does"
set -euo pipefail
...
```

`chmod +x` it and it appears in `mise tasks`.
