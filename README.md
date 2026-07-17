# talos-configs

Declarative configuration for my Talos Linux clusters, managed through [Omni](https://omni.siderolabs.com). Omni holds the running cluster state; this repo holds the **desired** state. Each cluster is a versioned [cluster template](https://docs.siderolabs.com/omni); `main` is the source of truth and CI reconciles Omni to it.

## Clusters

| Cluster | Control-plane machine | Node IP | Talos | Kubernetes | Notable |
|---|---|---|---|---|---|
| `management-cluster` | `03000200-…-0009` | 192.168.0.205 | v1.12.10 | v1.35.0 | Harbor registry mirrors + auth, control-plane VIP 192.168.0.30 |
| `private-cluster` | `0ac8680c-…-3418` | 192.168.0.204 | v1.12.10 | v1.35.0 | ArgoCD cluster-admin ServiceAccount for remote management |

Both are single-node control planes (`allowSchedulingOnControlPlanes: true`), Cilium CNI (Flannel + kube-proxy disabled), with local-path-provisioner as the default StorageClass.

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
mise.toml             # pinned toolchain + non-secret Azure config
omniconfig.yaml       # omnictl context (Omni endpoint + identity) — contains no secret
.env.example          # template for the two Azure service-principal values
```

## Getting a fresh clone working

The devpod's postCreate installs the toolchain. Secrets live in Azure Key Vault (`bde-dev-kv-homelab`) and are reached with an Azure service principal; the one value you supply by hand is that principal's client secret.

1. `cp .env.example .env` and fill `CLIENT_ID` + `CLIENT_SECRET` (only the secret is sensitive; tenant and vault are set in `mise.toml`).
2. `mise run fresh-clone` — pulls `SOPS_AGE_KEY`, `OMNI_ENDPOINT`, `OMNI_SERVICE_ACCOUNT_KEY` from Key Vault into `.env`, then fetches a talosconfig per cluster.
3. `mise run validate` — confirms decryption and the templates.

`fresh-clone` chains `bootstrap-env` and `gather-configs`; see `tasks/README.md`. `sops-init` is the fallback when Key Vault isn't available.

## How changes reach the clusters

`main` is the desired state and Omni reconciles to it — nothing is applied by hand.

1. Edit a `clusters/<name>/template.yaml` (or a patch).
2. `mise run validate` locally (also enforced by the `pre-push` hook).
3. Open a PR — the Diff workflow previews the exact resource changes a sync would make.
4. Merge to `main` — the Sync workflow applies the templates and waits for the clusters to report ready.

## CI

Three workflows, split by trigger:

- **`validate.yaml`** — push to any branch. Offline schema check (`omnictl cluster template validate`) of both templates.
- **`diff.yaml`** — pull request. `omnictl cluster template diff` previews what a sync would change, so the effect is visible at review time. It is informational and applies nothing.
- **`sync.yaml`** — push to `main`. Runs `validate` → `sync` (`omnictl cluster template sync`) → `wait` (`omnictl cluster template status --wait 15m`, with a 20-minute job backstop), so a merge applies the templates and blocks until Omni finishes the rollout.

Template `file:` includes carry `--allowed-dir ../..` because omnictl confines a template's file access to its own directory, and the shared patches live at the repo root (`../../shared-patches/…`).

## Upgrading Talos / Kubernetes

An upgrade is a template change, not a manual `talosctl upgrade` — Omni reconciles from the version fields:

1. Bump `talos.version` / `kubernetes.version` in each `clusters/<name>/template.yaml`.
2. `mise run validate`.
3. PR (the Diff preview shows the version change) → merge → Sync applies it and waits for ready.

Both clusters are single-node control planes, so an upgrade reboots the node with a brief outage. `omnictl get clusters` shows the current versions.

## Toolchain & auth

The devpod (`.devcontainer`) installs the pinned `mise` tools: `omnictl`, `talosctl`, `sops` + `age`, `yq`, and `azure-cli` (with `python` + `uv`, which back the Azure CLI install).

- **Secrets** live in Azure Key Vault `bde-dev-kv-homelab` and reach `.env` via `mise run bootstrap-env` (service-principal login). `.env` is gitignored and `mise` sources it into every task.
- **omnictl** authenticates with `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` from `.env`; CI uses the same values from GitHub secrets. The `omniconfig.yaml` interactive login is the fallback.
- **sops** decrypts with `SOPS_AGE_KEY` from `.env`, matched to the recipient in `.sops.yaml`.

## Local cluster access

`mise run gather-configs` builds `~/.talos/config` from Omni — a talosconfig per cluster with default node IPs filled in — so `talosctl` works without `--nodes`. See `tasks/README.md`.
