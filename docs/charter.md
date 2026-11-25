# Smol: charter

Smol is a small internal developer platform. A developer clicks **Create service** and gets a repo, CI, a dev deployment, cloud resources, a dashboard and PR previews, without touching Kubernetes.

A feature is in scope only if it serves one of Dana's jobs (§1.1) or meets an operator requirement (§1.2).

## 1. Users

### 1.1 Dana, backend developer

Works on `team-payments`, one of 6 product teams at a fictional 60-engineer company. The demo uses two teams, `team-payments` and `team-catalog`, the minimum needed to show O3. The golden-path template is Go, because a distroless `nonroot` image passes restricted Pod Security Standards with no workarounds.

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

_TODO: D1–D5 in order, then O2, O3, O5, O7 live. O8 isn't demoed._

## 3. Out of scope

_TODO_

## 4. Phase "done" criteria

_TODO: one check per phase, traced to D1–D5 and O1–O5._

## 5. Risks

_TODO: start with Floci coverage (RDS → CloudNativePG fallback) and Floci maturity (pin version, one endpoint override)._
