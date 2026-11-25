# Smol platform

Bootstrap, GitOps, Crossplane and Kyverno for Smol. See [`docs/charter.md`](docs/charter.md).

## Prerequisites

Supported hosts: Linux and macOS. On Windows, use WSL2 and follow the Linux steps. ([ADR-0001](docs/adr/0001-local-environment.md))

Install each tool from its official docs. The required version, or the compatibility rule, is in [`versions.env`](versions.env).

| Tool | Version rule | Needed from | Install docs |
|---|---|---|---|
| Docker Engine | ≥ `DOCKER_MIN_VERSION` | Phase 1 | Your distro's package (Ubuntu: `docker.io`) or https://docs.docker.com/engine/install/ |
| k3d | major `K3D_MAJOR` | Phase 1 | https://k3d.io/stable/#installation |
| kubectl | within ±`KUBECTL_MAX_SKEW` minor of the cluster | Phase 1 | https://kubernetes.io/docs/tasks/tools/ |
| Helm | major `HELM_MAJOR` | Phase 1 | https://helm.sh/docs/intro/install/ |
| ArgoCD CLI | same minor as `ARGOCD_VERSION` | Phase 1 | https://argo-cd.readthedocs.io/en/stable/cli_installation/ |
| GitHub CLI (`gh`) | ≥ `GH_MIN_VERSION` | Phase 1 | https://github.com/cli/cli#installation |
| Node.js + Corepack | major `NODE_MAJOR` | Phase 1 (Backstage) | https://nodejs.org/en/download, then `npm install -g corepack && corepack enable` |
| Crossplane CLI | same minor as `CROSSPLANE_VERSION` | Phase 3 | https://docs.crossplane.io/latest/cli/ |
| AWS CLI v2 | major `AWSCLI_MAJOR` | Phase 3 | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |

Node 25+ no longer bundles Corepack, so it is installed separately. Yarn itself is pinned by the Backstage repo. Cluster components (k3s, Floci, ArgoCD, Crossplane) are pinned exactly and installed by `make up`, not by hand.

Check your setup with `make doctor`. It checks every rule, installs nothing, and exits non-zero if a tool needed now is missing or wrong. Tools for later phases are reported but never fail the run.

## Repository settings

Branch rules are kept as code in [`.github/rulesets/`](.github/rulesets/). To create one on a fresh repo (to change an existing one, use `PUT .../rulesets/<id>`):

```bash
gh api -X POST repos/{owner}/{repo}/rulesets --input .github/rulesets/protect-main.json
```
