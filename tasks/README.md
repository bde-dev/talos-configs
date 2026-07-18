# Tasks

[mise](https://mise.jdx.dev) tasks for this repo. `mise.toml` wires this directory in via `[task_config] includes = ["tasks"]`, so any executable script here with a `#MISE description="…"` header comment is a task. List them with `mise tasks`; run one with `mise run <name>`.

| Task | What it does |
|---|---|
| `bootstrap-env` | Ensure `.env` has every required key (empty if unset) |
| `pull-secrets` | Pull the SOPS + Omni secrets from Azure Key Vault into `.env` |
| `sops-init` | Verify the SOPS age key in `.env` decrypts this repo |
| `validate` | Validate every cluster template against Omni |
| `gather-configs` | Build `~/.talos/config` from Omni with default node IPs |
| `fresh-clone` | Run all of the above in sequence |

Each task is atomic; `fresh-clone` chains them for a clean checkout.

## Getting a fresh clone working

```bash
mise run bootstrap-env     # scaffold .env with all keys (empty)
# fill CLIENT_ID + CLIENT_SECRET in .env (Azure SP, from the homelab azure-creds secret)
mise run fresh-clone       # pull secrets -> verify sops -> validate -> gather configs
```

`.env` holds two kinds of value: the Azure service-principal `CLIENT_ID` + `CLIENT_SECRET` you fill by hand (only the secret is sensitive; tenant and vault are non-secret in `mise.toml [env]`), and `SOPS_AGE_KEY` / `OMNI_ENDPOINT` / `OMNI_SERVICE_ACCOUNT_KEY`, which `pull-secrets` fills from Key Vault. `.env` is gitignored and mise sources it into every task.

## `bootstrap-env` — `bootstrap-env.sh`

The single `.env` scaffold: creates `.env` if absent and appends any missing key as an empty `KEY=` line. Idempotent — safe to re-run, and it never overwrites a value that is already set.

```bash
mise run bootstrap-env
```

## `pull-secrets` — `pull-secrets.sh`

Logs in to Azure with the service principal and pulls the repo's secrets from Key Vault `bde-dev-kv-homelab` into `.env`, so the only values you paste by hand are the SP `CLIENT_ID` / `CLIENT_SECRET`.

| Key Vault secret | `.env` variable |
|---|---|
| `omni-age-secret-key` | `SOPS_AGE_KEY` |
| `omni-endpoint` | `OMNI_ENDPOINT` |
| `omni-bootstrap-sa-key` | `OMNI_SERVICE_ACCOUNT_KEY` |

```bash
mise run pull-secrets
```

**Needs:** `azure-cli` (pinned in `mise.toml`) and `CLIENT_ID` / `CLIENT_SECRET` in `.env`. Idempotent — re-run to refresh.

## `sops-init` — `sops-init.sh`

Verifies the `SOPS_AGE_KEY` in `.env` is the right one: it derives the public key and checks it equals the recipient in `.sops.yaml`, so you know `sops` will decrypt before you rely on it. Exits non-zero if the key is missing or does not match.

```bash
mise run sops-init
```

**Needs:** `age` and a populated `SOPS_AGE_KEY` (from `pull-secrets`).

## `validate` — `validate.sh`

The local mirror of CI. For each `clusters/*/`: decrypts the `*.sops.yaml` patches in place, runs `omnictl cluster template validate -f template.yaml --allowed-dir ../..`, then restores the encrypted files via an `EXIT` trap so plaintext never lingers. Exits non-zero if any cluster fails. Also enforced by `.githooks/pre-push`.

```bash
mise run validate
```

**Needs:** `SOPS_AGE_KEY` in `.env`.

## `gather-configs` — `gather-configs.sh`

Builds `~/.talos/config` from Omni so `talosctl` reaches each cluster with no `--nodes` flag: fetches each cluster's talosconfig standalone (`omnictl talosconfig --merge=false`), accumulates them into a fresh config (distinct context names, no `-N` rename collisions), reads node IPs from Omni's `clustermachineidentity` resource, sets them as the context defaults, then swaps the built file into place and restores the previously-selected context.

```bash
mise run gather-configs
talosctl config contexts   # bde-dev-<cluster>, each with NODES populated
talosctl version           # hits the default node — no --nodes needed
```

`~/.talos/config` is a regenerable artefact of Omni: a rerun rebuilds it (dropping stale `-N` contexts) and does not preserve hand-added non-Omni contexts.

**Needs:** `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` in `.env` (from `pull-secrets`).

## `fresh-clone` — `fresh-clone.sh`

Runs the whole chain in order — `bootstrap-env` → `pull-secrets` → `sops-init` → `validate` → `gather-configs` — for a freshly cloned repo or rebuilt devpod. Fill `CLIENT_ID` / `CLIENT_SECRET` first; the rest flows from there.

```bash
mise run fresh-clone
```

## Adding a task

Drop an executable script here with a MISE header comment:

```bash
#!/bin/bash
#MISE description="what it does"
set -euo pipefail
...
```

`chmod +x` it and it appears in `mise tasks`.
