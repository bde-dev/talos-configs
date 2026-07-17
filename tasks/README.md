# Tasks

[mise](https://mise.jdx.dev) tasks for this repo. `mise.toml` wires this directory in via `[task_config] includes = ["tasks"]`, so any executable script here with a `#MISE description="…"` header comment becomes a task. List them with `mise tasks`; run one with `mise run <name>`.

| Task | What it does |
|---|---|
| `fresh-clone` | Bootstrap a fresh clone/devpod: run `sops-init` + `gather-configs` |
| `sops-init` | Scaffold `.env` for the SOPS age key, then verify it decrypts |
| `validate` | Validate every cluster template against Omni (decrypts secrets first) |
| `gather-configs` | Fetch a talosconfig per cluster from Omni and populate default node IPs |

## `fresh-clone` — `fresh-clone.sh`

One-shot bootstrap for a freshly cloned repo or a rebuilt devpod. Runs `sops-init` then `gather-configs`, so you land with a `.env` ready for the SOPS key and a populated `~/.talos/config`. It finishes by reminding you of the one manual step left.

```bash
mise run fresh-clone
# …paste the SOPS key into .env (see the reminder it prints)…
mise run validate
```

## `sops-init` — `sops-init.sh`

Gives you a place to paste the repo's SOPS **age private key** (kept in Bitwarden) so `sops` — and therefore `mise run validate` — can decrypt secrets in a fresh devpod. The key lives in `SOPS_AGE_KEY` inside `.env`: gitignored, sourced into every task by mise, and the same variable CI uses.

- **First run** creates `.env` with an empty `SOPS_AGE_KEY=` line and prints the recipient the key must match, plus the grab → paste → verify → validate steps.
- Paste the **AGE Secret Key** (the `AGE-SECRET-KEY-…` value, not the public key) from Bitwarden after `SOPS_AGE_KEY=`.
- **Re-run** to verify: it derives the public key from what you pasted and checks it equals the `.sops.yaml` recipient — so you know decryption will work before you rely on it.

```bash
mise run sops-init     # scaffolds .env, tells you what to paste
# …paste the key into .env…
mise run sops-init     # ✅ verifies it matches the repo recipient
mise run validate      # now decrypts cleanly
```

**Needs:** `age` (pinned in `mise.toml`). Idempotent and safe to re-run.

## `validate` — `validate.sh`

Mirrors CI. For each `clusters/*/`:

- Decrypts all `*.sops.yaml` in place, runs `omnictl cluster template validate -f template.yaml`, then restores the encrypted files via an `EXIT` trap — so plaintext never lingers, even if validation fails.
- Exits non-zero if any cluster fails.

```bash
mise run validate
```

**Needs:** the age key set up via `mise run sops-init` (or `SOPS_AGE_KEY` / a key file present some other way). Without it, encrypted patches are skipped with a warning and validation runs on what it can. Also enforced by `.githooks/pre-push`.

## `gather-configs` — `gather-configs.sh`

Rebuilds `~/.talos/config` from Omni so `talosctl` can talk to each cluster with no `--nodes` flag. For each `clusters/*/`:

1. Fetches that cluster's talosconfig standalone from Omni (`omnictl talosconfig --merge=false`) — the Omni endpoint is baked in.
2. Accumulates them into a fresh config (distinct context names, so no `-N` rename collisions).
3. Reads the cluster's node IPs from Omni's `clustermachineidentity` resource (scoped by the `omni.sidero.dev/cluster` label) and sets them as the context's default nodes.
4. Atomically swaps the built file into `~/.talos/config` and restores your previously-selected context.

```bash
mise run gather-configs
talosctl config contexts   # bde-dev-<cluster>, each with NODES populated
talosctl version           # hits the default node — no --nodes needed
```

**Idempotent** — safe to re-run; each run rebuilds cleanly and drops any stale `-N` duplicate contexts. It treats `~/.talos/config` as a **regenerable artefact of Omni**: a rerun will not preserve hand-added non-Omni contexts (for this repo, there are none).

**Needs:** an authenticated `omnictl` — either the `omniconfig.yaml` interactive login or `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` exported.

## Adding a task

Drop an executable script in this directory with a MISE header comment:

```bash
#!/bin/bash
#MISE description="what it does"
set -euo pipefail
...
```

`chmod +x` it and it appears in `mise tasks`.
