# Decision log

Things that surprised me while building Smol, and what I learned.

## 2026-11-25: tool versions and bootstrap

- **Exact pins for client CLIs don't hold up.** Package managers install the latest version (Homebrew), and distro packages freeze old ones (Ubuntu's `gh` was 2.45). So exact pins only cover what runs the platform (k3s, Floci, ArgoCD, Crossplane). Client tools get compatibility rules (kubectl ±1 minor of the cluster, CLI minor = server minor), and `make doctor` checks them.
- **Docker is a host prerequisite, not part of the platform.** A minimum version is enough; any distro package works.
- **Node 25+ dropped Corepack.** Backstage's setup still says `corepack enable`; install it with `npm i -g corepack`.
- **`floci start` defaults to `floci/floci:latest`, mounts the Docker socket, and uses the default bridge.** Confirmed on a container it created (2.5.0, socket mounted). `make floci` runs the pinned image from `floci/compose.yaml`; the Floci CLI is for status and logs only.
- **Floci needs the Docker socket only for container-backed services** (RDS, Lambda, ElastiCache, ECS, the web console). RDS runs real Postgres/MySQL containers, which lowers the charter's RDS-coverage risk. No socket until Phase 3 needs it.
- **Floci's image ships its own healthcheck and has no curl/wget.** Overriding the healthcheck broke it; `compose up --wait` works with the built-in one.
- **k3d expands `${VAR}` in its config unconditionally.** An unset `K3S_IMAGE` silently becomes k3d's default k3s version. `make cluster` refuses to run without it.

## 2026-11-25: ArgoCD cluster names

- **A cluster Secret for `https://kubernetes.default.svc` renames ArgoCD's `in-cluster` entry.** `argocd cluster list` then shows only the new name. An app with `name: in-cluster` still resolved in a test, but the docs don't promise that, so platform apps target the server URL.

## 2026-11-25: Backstage on Node 26

- **Backstage 1.56 supports Node 22/24 only; 1.57.0 is the first with 24/26.** `create-app@0.9.3` refuses Node 26. Took 1.57.1 as a pin-policy exception (ADR-0003).
- **`create-app@0.9.4` generates 1.57.0, not the latest patch.** `yarn backstage-cli versions:bump --release 1.57.1` afterwards.
- **The 1.57 template still uses a `node:24` base image**, and Node 25+ images ship no `yarn` or `corepack`. The Dockerfile now uses `node:26` (digest-pinned) and runs the Yarn release committed in `.yarn/releases/`.

## 2026-11-25: CloudNativePG under ArgoCD

- **CNPG's CRDs need server-side apply.** `clusters` (462 KiB) and `poolers` (662 KiB) exceed the 256 KiB annotation limit that client-side apply hits (`last-applied-configuration`). Upstream installs with `kubectl apply --server-side`; the app sets `ServerSideApply=true`.
- **The operator injects `caBundle` into its webhook configurations, and ArgoCD doesn't fight it.** The chart doesn't render `caBundle`, so under server-side apply the field is owned by the operator (`manager`, Update), not `argocd-controller`; selfHeal leaves it alone. No `ignoreDifferences` needed. Charts that render `caBundle: ""` would need one.
- **The mutating webhook defaults `spec.imageName`** (operator 1.30.2: `postgresql:18.7-system-trixie`). Pin the image in each `Cluster` so a CNPG upgrade doesn't silently change Postgres.

## 2026-11-25: root managing itself

- **Deleting a repo kills GitHub's redirect from its old URL.** The live `root` still pointed at the old owner, and nothing in git managed it, so it couldn't fetch its own fix. `root` now lives in `gitops/apps/` and manages itself (ADR-0002).
- **An app's drift on its own spec isn't healed immediately.** The controller drops watch events for the app's own object (`isSelfReferencedApp`, `controller/appcontroller.go` in v3.6.3) to avoid a refresh loop. A hand edit to `root` was reverted only after the next periodic reconcile (`timeout.reconciliation` 120 s + up to 60 s jitter) or a manual refresh. Child apps heal within seconds.

## 2026-11-25: Backstage chart vs. create-app config

- **The backstage chart and the `create-app` 1.57 template are incompatible out of the box.** The chart always sets `APP_CONFIG_backend_listen_port` (an object on the env layer); the template's `app-config.production.yaml` has `listen: ':7007'` (a string). Backstage won't merge an object over a string: `Invalid type in config for key 'backend.listen' … got string, wanted object`, crash on startup. Fix: object form (`listen: {port: 7007}`) in the image.
- **My smoke test missed it** because it loaded only `app-config.yaml`. A real check loads the same config layers the deployment uses, including env (`loadConfig` from `@backstage/config-loader`; a hand-built `ConfigReader` didn't reproduce it).
- **GHCR packages in an org are private by default**, unlike the first one under a personal account, and making one public needs the org's "Package creation: Public" setting first. Public is one-way.

## 2026-11-25: Floci emulates EKS

- **Floci 2.4.0 has an EKS API, contrary to what the project assumed.** Real mode (the default) starts one privileged k3s container per cluster through the Docker socket, with a working endpoint, IAM-authenticated access entries, Pod Identity injection and CloudWatch control-plane logs. Without the socket (our setup) clusters are metadata only. Addons and access policies are metadata, not enforced. The UI lists EKS as "running" because the API is enabled; `eks list-clusters` returns none.
- **Not adopted yet.** It would let a composition create a real `products` cluster locally (O8 for clusters, ADR-0002's multi-cluster path), at the cost of privileged containers and the Docker socket (root on the host). Decide with the Phase 3 Docker-socket ADR.

## 2026-11-27: Istio and Gateway API versions

- **Istio's newest release isn't on its old chart repo.** `istio-release.storage.googleapis.com/charts` stops at 1.31; 1.32 is only on `blob.istio.io/istio-release/charts`, the URL the docs give.
- **Istio's docs install Gateway API CRDs one minor behind upstream, from the experimental channel.** Istio 1.32 is built against v1.6.1 (`go.mod`) while upstream is at v1.7.0. Pinned v1.6.3 standard (ADR-0004).
- **The standard CRD bundle ships an admission policy.** `safe-upgrades.gateway.networking.k8s.io` (a ValidatingAdmissionPolicy, CEL in the API server, no webhook) rejects experimental CRDs over standard ones and bundles older than v1.5. Running Istio's documented `experimental-install.yaml` on this cluster later would be denied.
- **Istio's chart defaults assume a real cluster:** istiod requests 500m CPU / 2 GiB, ztunnel 200m / 512 MiB per node.
