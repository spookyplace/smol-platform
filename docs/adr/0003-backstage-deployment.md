# ADR-0003: Building and deploying Backstage

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

- Phase 1 needs Backstage with a catalog, deployed like everything else: by ArgoCD from git (O2).
- The app lives in its own repo, `smol-backstage` (CLAUDE.md layout). Its deployment config lives here, in `gitops/`.
- `make up` must work on a clean machine (O1). Backstage images will need signatures once Kyverno `verifyImages` lands (O5).
- Backstage needs a database. The official chart's Postgres subchart is Bitnami's, which now steers users to paid images.
- Backstage reads catalog files from GitHub. Anonymous GitHub API access is limited to 60 requests/hour per IP.

## Options

**Image build and delivery**

| Option | Pros | Cons |
|---|---|---|
| **CI builds and pushes to GHCR** (tag = git SHA) | Clean machine just pulls; same path as service repos (Trivy, Cosign later); tag in git is immutable | Needs the GitHub repo and Actions from day one |
| Host build, push to the local k3d registry | No CI needed; fast inner loop | `make up` needs a Backstage checkout at the exact SHA in git; images unsigned |

**Database**

| Option | Pros | Cons |
|---|---|---|
| **CloudNativePG** (operator + `Cluster`) | Real Postgres; same operator is the charter's RDS fallback (Phase 3) | One more operator in Phase 1 |
| SQLite in memory | Nothing to run | Lost on every restart (scaffolder history, sessions); not how anyone runs it |
| Chart's Bitnami subchart | One flag | Bitnami images moving behind a subscription; unpinned future |

**GitHub access for the catalog**

| Option | Pros | Cons |
|---|---|---|
| **GitHub App** (Backstage integration) | Short-lived installation tokens; needed for the scaffolder in Phase 2 anyway (O6) | App private key is a secret to handle now |
| Anonymous reads | Nothing to set up | 60 req/h per IP; catalog refresh breaks as it grows |

## Decision

- **Release:** Backstage `1.57.1`, an exception to the pin policy (1.57.0 is 8 days old). 1.56 supports only Node 22/24; 1.57 is the first to support Node 26, which `versions.env` pins. Upgrades with `backstage-cli versions:bump`.
- **Image:** host build (`yarn tsc`, `yarn build:backend`) in GitHub Actions, base image `node:26-trixie-slim` to match `NODE_MAJOR`, pushed to `ghcr.io/<owner>/smol-backstage:<sha>`. Bumping the tag in `gitops/` is a commit here.
- **Deploy:** `backstage/charts` chart `2.10.2` as a platform app (`server: https://kubernetes.default.svc`), with `postgresql.enabled: false`.
- **Database:** CloudNativePG operator as a platform app; one `Cluster` for Backstage. Credentials come from the Secret CNPG generates; nothing in git.
- **GitHub:** a GitHub App for the catalog now. Its private key goes into a Kubernetes Secret from a gitignored local file; never committed.
- **Sign-in (Phase 1):** guest provider, local only; GitHub sign-in in Phase 2 (O7).
- **Access (Phase 1):** `kubectl port-forward`; Istio Gateway in Phase 2.

## Consequences

- `make up` pulls a prebuilt image; no Node build on the clean-machine path. Node is only needed to develop Backstage.
- The GitHub App key is a long-lived credential on the workstation and in the cluster. It's the standard for GitHub Apps; noted in `docs/security.md`.
- Two version lines to bump: Backstage (`backstage.json` in `smol-backstage`) and the chart (here).
- The policy exception carries the risk the 14-day rule exists for: regressions in a fresh minor. Mitigation: pin the patch, take 1.57.x patches as they land.
- CNPG backups and HA are out of scope locally; one instance.

## References

- [Backstage: Node.js support (versioning policy)](https://backstage.io/docs/overview/versioning-policy#nodejs-releases)
- [Backstage: Docker host build](https://backstage.io/docs/deployment/docker/)
- [Backstage Helm chart](https://github.com/backstage/charts/tree/main/charts/backstage)
- [Backstage: GitHub Apps](https://backstage.io/docs/integrations/github/github-apps)
- [CloudNativePG](https://cloudnative-pg.io/documentation/current/)
- [GitHub REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
