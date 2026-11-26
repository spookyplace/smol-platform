# Smol: charter

Smol is a small internal developer platform. A developer clicks **Create service** and gets a repo, CI, a dev deployment, cloud resources, a dashboard and PR previews, without touching Kubernetes.

A feature is in scope only if it serves one of Dana's jobs (§1.1) or meets an operator requirement (§1.2).

## 1. Users

### 1.1 Dana, backend developer

Works on `team-payments`, one of 6 product teams at a fictional 60-engineer company. The demo uses two teams, `team-payments` and `team-catalog`, the minimum needed to show O3. Dana and one `team-catalog` member are separate real GitHub accounts, so sign-in (O7) and cross-team denials are shown live. The golden-path template is Go, because a distroless `nonroot` image passes restricted Pod Security Standards with no workarounds.

- **Knows:** Git, PRs, one backend language, basic Docker, SQL.
- **Shouldn't need to know:** Kubernetes, Helm, ArgoCD, Crossplane, Kyverno, Istio, AWS IAM.

| # | Job | Today | Target |
|---|---|---|---|
| D1 | Start a new service | Copy an old repo's chart and CI | Create → healthy pod in dev in < 15 min; repo comes with CI (Trivy, Cosign, SBOM), CODEOWNERS and branch protection without Dana asking |
| D2 | Get a database or bucket | Ticket, days | Self-service from the portal, no cloud credentials |
| D3 | Review a change live | None | Preview URL per PR in < 5 min, removed on merge |
| D4 | See service health and maturity | Build own dashboards | Dashboard and scorecard exist automatically |
| D5 | Understand a blocked deploy | Raw webhook error in a sync log | Policy name + fix hint in the portal |

Dana writes zero Kubernetes manifests. The D1 and D3 targets get checked in Phase 2 and lowered openly if they don't hold.

**Not for:** frontend-only, data/ML or batch workloads; teams needing raw manifests; multi-cluster production.

### 1.2 Operator requirements

| # | Requirement | Check |
|---|---|---|
| O1 | Bootstrap from zero | `make up` on a clean machine (per README prerequisites) works with no manual edits; `make down` removes it |
| O2 | Git is the only way to change things | A `kubectl edit` made by hand is reverted by ArgoCD |
| O3 | Teams are isolated | `team-catalog` can't deploy to or claim infra in `team-payments`; cross-team traffic is denied by default (NetworkPolicy + Istio ambient mTLS) |
| O4 | Change once, applies everywhere | One PR changes the template, Composition or policy for all teams; one PR adds a team |
| O5 | Controls are provable | Signed image admitted, unsigned rejected; a privileged pod rejected by restricted PSS; both shown in the portal |
| O6 | No long-lived credentials | No static cloud or GitHub keys in repos or cluster: GitHub App for Backstage, OIDC for CI, secret scanning in CI |
| O7 | Portal access control | Real sign-in; a user outside the owning team can't run its templates or act on its services |
| O8 | Cloud-portable infra (not demoed) | Compositions are identical for Floci and AWS; only the ProviderConfig differs |

## 2. Demo script

Target: ≤ 12 min video, one take per act, waits cut and timers shown on screen. Starts from a running `make up` (O1 shown as a time-lapse, not live).

**Act 1: Dana (developer)**

| # | Step | Shows | Traces to |
|---|---|---|---|
| 1 | Dana signs in with GitHub; sees her team's catalog | Real sign-in, ownership | O7 |
| 2 | Create service → Go template → `payments-api` | Repo with CI, CODEOWNERS, branch protection; registration PR to `smol-platform` | D1, O6 |
| 3 | CI goes green (Trivy, Cosign, SBOM); ArgoCD deploys; pod healthy in dev | Timer < 15 min | D1 |
| 4 | Request a Postgres database from the portal; service connects | No cloud credentials; claim in own namespace | D2 |
| 5 | Open a PR → preview URL → merge → preview gone | Timer < 5 min | D3 |
| 6 | Entity page: dashboard and scorecard | Created automatically | D4 |
| 7 | Push a change that runs as root → deploy blocked; portal shows policy + fix hint; fix → deployed | Admission, in Dana's words | D5, O5 |

**Act 2: operator (platform team)**

| # | Step | Shows | Traces to |
|---|---|---|---|
| 8 | `kubectl edit` a deployment → reverted | GitOps as the only write path | O2 |
| 9 | Unsigned image → rejected; signed → admitted | `verifyImages` | O5 |
| 10 | `team-catalog` user can't run payments' template or act on `payments-api` | Permission framework | O7 |
| 11 | `team-catalog` app targeting `team-payments` → AppProject denies; cross-namespace request → denied | Tenant isolation | O3 |
| 12 | One PR to the shared chart/policy → applies to every service | Change once | O4 |

## 3. Out of scope

| Out | Why |
|---|---|
| Production: HA control plane, multi-region, DR, backups beyond CNPG defaults | Laptop demo; documented as gaps in `security.md` |
| Multi-cluster at runtime | Hub/spoke designed for (ADR-0002), one cluster built |
| Real AWS in the demo | Optional Terraform module only (O8 not demoed) |
| Templates other than Go | One golden path, done properly |
| Frontend, data/ML, batch workloads | Not Dana's jobs (§1.1) |
| Migrating or importing existing services | Greenfield only |
| External secrets manager (Vault, ESO) | Crossplane connection secrets + GitHub App cover the demo; noted in `security.md` |
| Cost reporting, FinOps | No real spend |
| Custom Backstage theme/branding | No user value for the demo |

## 4. Phase "done" criteria

| Phase | Done when | Traces to | Status |
|---|---|---|---|
| 1 Foundation | `make down && make up` on a machine with the README prerequisites → Backstage serving the catalog, no manual steps beyond `local.env` | O1 | ✓ 2026-11-25: ~4.5 min |
| | A hand edit to a managed resource is reverted by ArgoCD | O2 | ✓ ~2 s (child app) |
| | ArgoCD, CNPG and Backstage are installed and upgraded only from git | O2, O4 | ✓ |
| 2 Golden path | "Create service" → repo with CI (Trivy, Cosign, SBOM), CODEOWNERS and branch protection → healthy pod in dev, < 15 min | D1, O6 | |
| | GitHub sign-in; a user outside the owning team can't run its template | O7 | |
| | `team-catalog` can't deploy into `team-payments` (AppProject) or reach it over the network | O3 | |
| 3 Self-service infra | Database or bucket requested from the portal, ready without cloud credentials | D2, O6 | |
| | PR → preview URL < 5 min, removed on merge | D3 | |
| | Same Composition works with the `local` and `aws` ProviderConfig (not demoed) | O8 | |
| 4 Guardrails and insight | Unsigned image and privileged pod rejected at admission; policy name + fix hint shown in the portal | D5, O5 | |
| | New service gets a dashboard and scorecard automatically | D4 | |
| 5 Polish | Demo video covering §2; ADRs current; EKS module applies cleanly | all | |

## 5. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Floci service coverage (RDS, IAM, EKS) | Phase 3 claims fail locally | RDS: CloudNativePG fallback, already running. EKS real mode exists in 2.4 but needs the Docker socket; decide in Phase 3 |
| Floci maturity | Breaking changes, bugs | Pinned version; endpoint override in one place |
| Fresh upstream releases | Regressions | Pin policy in `versions.env` (minor ≥ 14 days, newest patch). Exception: Backstage 1.57 for Node 26 (ADR-0003) |
| Upstream defaults that don't fit together | Startup failures (e.g. Backstage chart vs. `create-app` config) | Smoke test with the deployment's real config layers; decision log |
| Third-party images change terms | Unpullable or paid images (Bitnami) | Avoid Bitnami subcharts; pin digests |
| GitHub free-tier limits (GHCR, Actions) | Builds or pulls blocked | Public packages are free; add image retention (Phase 2) |
| Laptop resources | Cluster too slow or OOM with Istio, Prometheus, Crossplane | Resource requests on every component; measure each phase |
| Single maintainer | No required reviews on `main` | Rulesets, CI checks; documented in `security.md` |
