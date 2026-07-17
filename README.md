# talos-configs

Declarative configuration for my Talos Linux clusters, managed through [Omni](https://omni.siderolabs.com). Omni holds the running cluster state; this repo holds the **desired** state — each cluster is a versioned [cluster template](https://docs.siderolabs.com/omni) that CI validates on every PR and syncs to Omni on merge to `main`.

## Clusters

| Cluster | Control-plane machine | Node IP | Talos | Kubernetes | Notable |
|---|---|---|---|---|---|
| `management-cluster` | `03000200-…-0009` | 192.168.0.205 | v1.12.2 | v1.35.0 | Harbor registry mirrors + auth, control-plane VIP 192.168.0.30 |
| `private-cluster` | `0ac8680c-…-3418` | 192.168.0.204 | v1.12.2 | v1.35.0 | ArgoCD cluster-admin ServiceAccount for remote management |

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
.github/workflows/    # CI: validate on PR, sync to Omni on merge to main
.sops.yaml            # SOPS/age rules (encrypts username/password keys)
mise.toml             # pinned toolchain: omnictl, talosctl, sops, age, yq
omniconfig.yaml       # omnictl context (Omni endpoint + identity) — contains no secret
```

## Bootstrapping a fresh clone

After opening the repo in the devpod (postCreate installs the toolchain), get it working with one task:

```bash
mise run fresh-clone      # scaffolds .env for the SOPS key + fetches talosconfigs from Omni
```

Then finish the one manual step — the SOPS age key is not in git:

1. In Bitwarden, copy the **AGE Secret Key** — the `AGE-SECRET-KEY-…` value, not the public key.
2. Paste it into `.env` after `SOPS_AGE_KEY=` (`.env` is gitignored).
3. `mise run validate` — confirms decryption works and validates the templates.

`fresh-clone` just chains `sops-init` and `gather-configs`; see `tasks/README.md`.

## How changes flow

1. Edit a `clusters/<name>/template.yaml` (or one of its patches).
2. `mise run validate` — decrypts secrets, validates every template against Omni, restores encryption.
3. Commit and open a PR → CI runs the same validation.
4. Merge to `main` → CI's `sync` job runs `omnictl cluster template sync` per cluster → Omni reconciles the clusters to match.

Nothing is applied by hand — Omni does the reconciliation from the synced template.

## Upgrading Talos / Kubernetes

Because Omni reconciles from the template, an upgrade is a config change — **not** a manual `talosctl upgrade`:

1. Bump `talos.version` and/or `kubernetes.version` in each `clusters/<name>/template.yaml`.
2. `mise run validate`.
3. PR → merge → CI's `sync` rolls the upgrade out through Omni.

Confirm with `omnictl get clusters` (shows each cluster's current Talos + Kubernetes version) before and after.

## Toolchain & auth

Everything runs inside the devpod (`.devcontainer`), which installs the pinned tools via `mise`:

- `omnictl` — Omni API client (templates, sync, resources)
- `talosctl` — Talos node API (auth comes from Omni; see `tasks/README.md`)
- `sops` + `age` — secret encryption
- `yq` — YAML wrangling

**omnictl auth** comes from `omniconfig.yaml` (endpoint + identity → interactive OIDC login). CI instead uses a service account via `OMNI_ENDPOINT` + `OMNI_SERVICE_ACCOUNT_KEY` — export those locally too if you want to skip the browser login.

**Secret decryption** needs the age private key for the recipient in `.sops.yaml`, as a key file or `SOPS_AGE_KEY`. Run `mise run sops-init` to scaffold `.env` for the key and verify it (see `tasks/README.md`). Without it, `validate` skips the encrypted patches with a warning.

## Local cluster access

`mise run gather-configs` pulls a talosconfig per cluster from Omni and fills in the default node IPs, so `talosctl` works without `--nodes`. See `tasks/README.md`.
