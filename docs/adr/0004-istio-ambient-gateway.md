# ADR-0004: Istio ambient mesh and Gateway API ingress

- **Status:** Accepted
- **Date:** 2026-11-27

## Context

- Phase 1 reaches Backstage and ArgoCD through `kubectl port-forward`. Phase 2 needs stable URLs: GitHub sign-in (O7) and ArgoCD SSO need fixed callback URLs, and D3 needs a URL per preview.
- CLAUDE.md fixes the stack: Istio ambient (ztunnel L4 mTLS, waypoints only for L7 policy), Istio Gateway via Gateway API as ingress, namespaces opt in with `istio.io/dataplane-mode=ambient`, default-deny NetworkPolicies stay (O3).
- k3d (ADR-0001) already disables Traefik and maps `127.0.0.1:8080→80` and `127.0.0.1:8443→443` on its load balancer. k3s ServiceLB (klipper) is on.
- Workstation: WSL2; the browser runs on Windows and reaches WSL's `127.0.0.1` ports through localhost forwarding.
- This ADR decides install, CRDs, DNS, TLS and tenant routing. NetworkPolicies themselves come with O3.

## Options

**Install method**

| Option | Pros | Cons |
|---|---|---|
| **Helm charts (`base`, `istiod`, `cni`, `ztunnel`) as ArgoCD sources** | Istio's recommended path for ambient; same model as ArgoCD/CNPG/Backstage (ADR-0002); control and data plane upgrade separately | Four charts at one version to keep in step |
| `istioctl install` from `make` | One command | Imperative; bypasses GitOps (O2) |
| Sail operator | CR-driven lifecycle | Another operator; less common outside OpenShift |

**Gateway API CRD channel**

| Option | Pros | Cons |
|---|---|---|
| **Standard** | Stable APIs only; v1.6 standard already has Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, TLSRoute, ListenerSet, BackendTLSPolicy | Experimental fields unavailable |
| Experimental (what Istio's docs install) | Everything Istio can use | Experimental CRDs can break between minors; the v1.6 `safe-upgrades` ValidatingAdmissionPolicy makes going back to standard awkward |

**Local DNS**

| Option | Pros | Cons |
|---|---|---|
| **`*.localhost`** (RFC 6761) | Wildcard; no third-party DNS; works offline; browsers and curl resolve it to loopback themselves; a secure context in browsers even over HTTP | glibc in WSL doesn't resolve it (tested: `getent` fails, curl 8.5 works), so some CLIs need `/etc/hosts` entries or port-forward |
| `*.localtest.me` / `nip.io` | Real public DNS, every tool resolves it | Depends on a third-party domain; breaks offline; not a secure context over HTTP |
| `/etc/hosts` | Every tool resolves it | No wildcards: each preview environment (D3) would need a manual edit, breaking O1 |

**TLS at the gateway (Phase 2)**

| Option | Pros | Cons |
|---|---|---|
| **HTTP only, loopback bind** | No trust-store setup; `make up` stays hands-free (O1) | Ingress hop is plaintext (loopback only); demo shows `http://` |
| cert-manager + local CA | Real HTTPS | CA must be trusted in the Windows browser store from WSL: a manual step per machine |

**Tenant hostnames**

| Option | Pros | Cons |
|---|---|---|
| **One shared Gateway, one listener per team** (`*.<team>.localhost`, `allowedRoutes` limited to that team's namespaces) | Gateway API enforces it: a route can only attach to its own team's listener, so `team-catalog` can't claim a payments hostname (O3) | Adding a team edits the Gateway (one line in the add-team PR, fine for O4) |
| One listener, Kyverno checks HTTPRoute hostnames | Gateway never changes | Isolation depends on a Phase 4 component; hostname conflicts resolve by route age |
| ListenerSet per team | Teams own their listeners | New in standard; Istio 1.32 support not verified |

## Decision

- **Versions:** Istio `1.32.0` (charts from `https://istio-release.storage.googleapis.com` don't carry 1.32; use `https://blob.istio.io/istio-release/charts`, as the docs say). Supports Kubernetes 1.33–1.37 (we run 1.36).
- **Gateway API CRDs:** `v1.6.3`, standard channel. **Pin-policy exception:** the policy picks v1.7.0, but Istio 1.32 is built and documented against v1.6.1 (`go.mod`, release-1.32 docs). Rule: compatibility with the consumer wins; take the newest patch of the supported minor. Move to 1.7 with the Istio minor that supports it.
- **Apps (all platform apps, `kubernetes.default.svc`):**
  - `gateway-api`: directory source `kubernetes-sigs/gateway-api` at tag `v1.6.3`, path `config/crd/standard`, ServerSideApply (CRDs exceed the client-side annotation limit).
  - `istio`: multi-source app with `base`, `istiod`, `cni`, `ztunnel` at one version, `profile: ambient`, `global.platform: k3s` (sets k3s CNI paths). Not `k3d`, which the docs suggest: its profile has a stale `cniBinDir` (see decision log, 2026-11-27). Istio's `base` chart manages its CRDs as templates (`enableCRDTemplates: true`), so they upgrade with the chart.
  - `ingress`: `gitops/ingress/`: namespace `istio-ingress`, the shared `Gateway` (class `istio`; istiod deploys it as a Deployment + LoadBalancer Service that k3s ServiceLB binds to ports 80/443), and HTTPRoutes for platform UIs.
  - Ordering between apps by retry with backoff, as for Backstage (ADR-0003): waves can't order sibling apps.
- **Resources:** explicit, smaller requests (chart defaults: istiod 500m/2Gi, ztunnel 200m/512Mi per node). Measure and record actual usage.
- **Hostnames:** `http://<app>.localhost:8080`. Platform: `backstage`, `argocd` (later `grafana`). Services: `<svc>.<team>.localhost`; previews: `pr-<n>-<svc>.<team>.localhost` (single label under the team, Phase 3).
- **Listeners:** `platform` (`*.localhost`, routes only from platform namespaces) and one per team (`*.<team>.localhost`, routes only from namespaces labelled with that team).
- **TLS:** HTTP only in Phase 2, bound to `127.0.0.1`. Listed as a gap in `security.md`; in-mesh traffic is mTLS via ztunnel either way.
- **Mesh enrolment now:** `backstage` (app + CNPG database), as the first real workload in ambient before any generated service. Not `istio-system`, `kube-system`, `argocd`, `cnpg-system`. Team namespaces get the label from the scaffolder (Phase 2) and Kyverno requires it (Phase 4).
- **App changes:** Backstage `app.baseUrl`/`backend.baseUrl` → `http://backstage.localhost:8080`; ArgoCD `server.insecure: true` (gateway terminates), UI at `http://argocd.localhost:8080`. Port-forward stays documented as a fallback.

## Consequences

- No manual step on a clean machine; URLs are stable for OAuth callbacks.
- **Unverified, test while building:**
  - GitHub accepts `http://backstage.localhost:8080/...` as an App callback URL.
  - The Windows browser reaches `*.localhost:8080` through WSL localhost forwarding.
  - Go CLIs (argocd) resolving `*.localhost` in WSL. If not: `/etc/hosts` entry (workstation notes) or port-forward.
  - istiod rewrites its webhook config at runtime (caBundle, failurePolicy); expect an `ignoreDifferences` entry.
- `*.localhost` also matches `<svc>.<team>.localhost` (wildcards are suffix matches). The more specific team listener wins, but a platform route could still claim a team hostname unless Istio implements Listener Isolation (Extended; unverified). Only platform namespaces can attach, so low risk; test with the first team listener.
- Future default-deny NetworkPolicies must allow TCP 15008 (HBONE) and the kubelet-probe SNAT source `169.254.7.127/32` (and the IPv6 equivalent) for enrolled pods, or probes and mesh traffic fail.
- Removing Istio needs care: unlabel namespaces while ztunnel and CNI still run, or enrolled pods lose connectivity. `make down` deletes the whole cluster, so this only matters for in-place removal.
- A ztunnel upgrade restarts the node proxy and drops that node's connections. Accepted locally; real clusters would roll nodes.
- Two pinned lines to bump in step: Istio charts and the Gateway API tag. `check-pins` covers both.
- Plain HTTP at the edge is a local-only compromise; a real environment uses cert-manager + ACME on the same Gateway.

## References

- [Istio: supported releases](https://istio.io/latest/docs/releases/supported-releases/)
- [Istio: install ambient with Helm](https://istio.io/latest/docs/ambient/install/helm/)
- [Istio: ambient platform prerequisites (k3d)](https://istio.io/latest/docs/ambient/install/platform-prerequisites/)
- [Istio: ambient and Kubernetes NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/)
- [Istio: Gateway API automated deployment](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/#automated-deployment)
- [Gateway API: release channels](https://gateway-api.sigs.k8s.io/concepts/versioning/)
- [RFC 6761 §6.3: `.localhost`](https://www.rfc-editor.org/rfc/rfc6761#section-6.3)
