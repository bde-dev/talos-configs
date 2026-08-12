# talos-configs

Declarative configuration for my Talos Linux clusters, managed through [Omni](https://omni.siderolabs.com). Omni holds the running cluster state; this repo holds the **desired** state. Each cluster is a versioned [cluster template](https://docs.siderolabs.com/omni); `main` is the source of truth and CI reconciles Omni to it.

## Clusters

| Cluster | Control-plane machine | Node IP | Notable |
|---|---|---|---|
| `management-cluster` | `03000200-…-0009` | 192.168.0.205 | Harbor registry mirrors + auth, control-plane VIP 192.168.0.30 |
| `private-cluster` | `0ac8680c-…-3418` | 192.168.0.204 | ArgoCD cluster-admin ServiceAccount for remote management, control-plane VIP 192.168.0.31 |
| `public-cluster` | `86ebeb1e-…-4e90` | 192.168.0.82 | ArgoCD cluster-admin ServiceAccount for remote management, control-plane VIP 192.168.0.32 |
| `runners-cluster` | `TODO-UUID-run-cp-01` | 192.168.0.206 (planned) | 1 control plane + 2 workers (`run-wk-01`/`run-wk-02`, planned 192.168.0.207/.208) on EliteDesk 800 minis; control-plane VIP 192.168.0.33; placeholder machine UUIDs — do not sync until the hardware arrives |

`management-cluster`, `private-cluster` and `public-cluster` are single-node control planes; `runners-cluster` is 1 control plane + 2 dedicated workers (scaffolded — hardware not yet purchased, so its template holds placeholder machine UUIDs and must not be synced). All clusters allow workload scheduling on control planes (`allowSchedulingOnControlPlanes: true`), run Cilium CNI (Flannel + kube-proxy disabled), and use local-path-provisioner as the default StorageClass. Talos and Kubernetes versions are pinned per cluster in `clusters/<name>/template.yaml`.

## Layout

```
clusters/<name>/
  template.yaml       # Omni cluster template — pins Talos + K8s version, lists patches
  patches/            # cluster-specific patches (incl. SOPS-encrypted secrets)
shared-patches/       # patches shared across clusters (registry mirrors, CNI, volumes, storage)
tasks/                # mise tasks — see tasks/README.md
scripts/setup         # devcontainer postCreate: mise install + argo helm repo
.devcontainer/        # the devpod this repo is worked from
.githooks/pre-push    # runs `mise run validate` before every push
.github/workflows/    # validate.yaml, diff.yaml, sync.yaml (see CI below)
.sops.yaml            # SOPS/age rules (encrypts username/password keys)
mise.toml             # pinned toolchain + non-secret Azure config (tenant, vault, client id)
omniconfig.yaml       # omnictl context (Omni endpoint + identity) — contains no secret
renovate.json         # version tracking for the templates (dormant until activated)
```

## Getting a fresh clone working

The devpod's postCreate installs the toolchain. Secrets live in Azure Key Vault (`bde-dev-kv-homelab`), reached with an Azure service principal whose non-secret ids (tenant, vault, client id) are in `mise.toml [env]`. The one value you supply by hand is the principal's **client secret** — as a shell `export` or a line in `.env`.

```bash
mise run bootstrap-env      # ensure .env holds the keys it needs (skips anything already set)
export CLIENT_SECRET=…      # or add CLIENT_SECRET=… to .env
mise run fresh-clone        # pull secrets -> verify sops -> validate -> gather configs
```

See `tasks/README.md` for the individual tasks.

## How changes reach the clusters

`main` is the desired state and Omni reconciles to it — nothing is applied by hand.

1. Edit a `clusters/<name>/template.yaml` (or a patch).
2. `mise run validate` locally (also enforced by the `pre-push` hook).
3. Open a PR — the Diff workflow previews the exact resource changes a sync would make.
4. Merge to `main` — the Sync workflow applies the templates and waits for the clusters to report ready.

## CI

Three workflows, split by trigger:

- **`validate.yaml`** — push to any branch. Offline schema check (`omnictl cluster template validate`) of every template.
- **`diff.yaml`** — pull request. `omnictl cluster template diff` previews what a sync would change, so the effect is visible at review time. It is informational and applies nothing.
- **`sync.yaml`** — push to `main`. Runs `validate` → `sync` (`omnictl cluster template sync`) → `wait` (`omnictl cluster template status --wait 15m`, with a 20-minute job backstop), so a merge applies the templates and blocks until Omni finishes the rollout.

Template `file:` includes carry `--allowed-dir ../..` because omnictl confines a template's file access to its own directory, and the shared patches live at the repo root (`../../shared-patches/…`).

## Upgrading Talos / Kubernetes

An upgrade is a template change, not a manual `talosctl upgrade` — Omni reconciles from the version fields:

1. Bump `talos.version` / `kubernetes.version` in each `clusters/<name>/template.yaml`.
2. `mise run validate`.
3. PR (the Diff preview shows the version change) → merge → Sync applies it and waits for ready.

The deployed clusters are single-node control planes, so a Talos upgrade reboots the node with a brief outage; a Kubernetes upgrade restarts the control-plane pods and kubelet without an OS reboot. Kubernetes moves one minor at a time and is capped by the running Talos version's supported range. `omnictl get clusters` shows the current versions.

## Toolchain & auth

The devpod (`.devcontainer`) installs the pinned `mise` tools: `omnictl`, `talosctl`, `sops` + `age`, `yq`, and `azure-cli` (with `python` + `uv`, which back the Azure CLI install).

- **Secrets** live in Azure Key Vault `bde-dev-kv-homelab`. `mise run pull-secrets` logs in with the service principal and writes `SOPS_AGE_KEY` / `OMNI_ENDPOINT` / `OMNI_SERVICE_ACCOUNT_KEY` into `.env`. `.env` is gitignored and mise sources it into every task.
- **omnictl** authenticates with `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` from `.env`; CI uses the same values from GitHub secrets.
- **sops** decrypts with `SOPS_AGE_KEY` from `.env`, matched to the recipient in `.sops.yaml`.

## Local cluster access

`mise run gather-configs` builds `~/.talos/config` from Omni — a talosconfig per cluster with default node IPs filled in — so `talosctl` works without `--nodes`. See `tasks/README.md`.
