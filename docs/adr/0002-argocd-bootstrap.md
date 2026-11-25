# ADR-0002: Installing and bootstrapping ArgoCD

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

- ArgoCD is the only way to change the cluster after bootstrap (charter O2), so something other than ArgoCD has to install it first.
- `make up` must work on a clean machine with no manual edits (O1).
- No long-lived credentials (O6). `smol-platform` is a public repo, so ArgoCD can read it without any.
- ArgoCD's version is pinned in `versions.env` (`ARGOCD_VERSION`).
- One cluster for now, but platform and products may split into separate clusters later (hub and spoke). Destinations must not assume one cluster.

## Options

**Install method**

| Option | Pros | Cons |
|---|---|---|
| **Helm chart** (`argo/argo-cd`, community-maintained) | One values file for all config (`argocd-cm`, RBAC, resources); chart version pins the app version; same chart for bootstrap and self-management | Community chart, one step behind upstream releases; chart version ≠ app version, so two pins |
| Upstream manifests (`install.yaml`) + Kustomize | Official artefact; one pin | Config via Kustomize patches on ConfigMaps; more YAML to keep in sync |
| ArgoCD Operator / Autopilot | Operator manages upgrades; Autopilot generates the repo layout | Extra component and CRD; Autopilot owns the repo layout and is little used |

**Who manages ArgoCD after install**

| Option | Pros | Cons |
|---|---|---|
| **Self-managed:** an `Application` installs the same chart with the same values | Upgrades and config changes are PRs (O2, O4); drift is reverted | A bad values change can break ArgoCD itself; recovery is re-running `make argocd` |
| Bootstrap only, upgrades by `helm upgrade` | Simple; no self-reference | ArgoCD config is outside GitOps; breaks O2 |

## Decision

- **Install:** `make argocd` runs `helm upgrade --install` of `argo/argo-cd`, pinned by `ARGOCD_CHART_VERSION` (app version `ARGOCD_VERSION`), with `gitops/argocd/values.yaml`. Idempotent; it is also the recovery path.
- **Root app:** `make argocd` then applies one `Application` (`gitops/root.yaml`) pointing at `gitops/apps/` on `main` of `smol-platform`. Everything else, ArgoCD included, is a child `Application` there (app-of-apps).
- **Self-managed:** `gitops/apps/argocd.yaml` installs the same chart and version with the same `values.yaml` as `make argocd`, so the two can't drift.
- **Destinations by role:** platform apps (ArgoCD, later Crossplane, Backstage) use `server: https://kubernetes.default.svc`, which is always ArgoCD's own cluster. Workload apps, ApplicationSets and team `AppProject`s use `destination.name: products`. Today `products` is a cluster Secret (chart `configs.clusterCredentials`) pointing at this cluster.
- **Sync policy:** automated with `prune` and `selfHeal` on every app (O2).
- **Access (Phase 1):** `kubectl port-forward` only; the `admin` user with the generated initial password. Exposed through the Istio Gateway in Phase 2.

## Consequences

- Two pins to keep together: chart version and app version. `make doctor` checks that the CLI minor matches `ARGOCD_VERSION`.
- ArgoCD syncs from GitHub, so unpushed local changes are never applied. Testing a change means pushing a branch and pointing an app at it, or `argocd app diff --local`.
- A fork has to change the `repoURL` in `gitops/`; the repo URL is set in one place per file and documented.
- The admin account is a local shortcut. SSO for ArgoCD and disabling `admin` are noted in `docs/security.md`.
- Splitting clusters later means changing the `products` entry's `server` and credentials, not every app. That credential would be long-lived locally (a ServiceAccount token, against O6); on EKS, IAM-based auth instead. Where Crossplane runs, and how connection secrets reach a separate products cluster, needs its own ADR before that split.
- The `products` Secret renames ArgoCD's `in-cluster` entry. `name: in-cluster` still resolved in a test, but that isn't documented, so platform apps don't rely on it.
- If ArgoCD breaks itself, `make argocd` reinstalls from the same values; ArgoCD then adopts the release again.

## References

- [Declarative setup: manage Argo CD using Argo CD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#manage-argo-cd-using-argo-cd)
- [Cluster bootstrapping: app of apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [argo-helm `argo-cd` chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
- [Clusters (declarative setup)](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
- [Automated sync policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
