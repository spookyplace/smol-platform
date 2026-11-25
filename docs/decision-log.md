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
