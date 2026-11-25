# ADR-0001: Local runtime and supported hosts

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

- Smol must come up on a laptop with one command (charter O1) and be easy to recreate.
- It needs a Kubernetes cluster plus an AWS emulator (Floci) that Crossplane in the cluster can reach.
- Reviewers run Linux, macOS or Windows.

## Options

**Cluster**

| Option | Pros | Cons |
|---|---|---|
| **k3d** (k3s in Docker) | Lightweight; built-in load balancer for port mapping; creates a local registry (`--registry-create`) | k3s, not upstream Kubernetes; ships Traefik (disabled, since Istio Gateway replaces it) |
| kind | Upstream Kubernetes | LoadBalancer needs the separate `cloud-provider-kind`; local registry needs a setup script |
| minikube | Mature; many add-ons | Heavier; behavior depends on the chosen driver |

**Floci placement**

| Option | Pros | Cons |
|---|---|---|
| **Container on host Docker, attached to the k3d network** | Survives cluster recreation; sits outside the cluster like real AWS | One extra container to manage in `make up` |
| Pod in the cluster | One thing to manage | State is lost on `make down`; blurs the cluster/cloud trust boundary |

## Decision

- **k3d**, with the k3s (Kubernetes) version pinned in `versions.env`.
- **Floci on host Docker**, attached to the k3d network, with its image tag pinned in `versions.env`. The endpoint is defined in one place.
- **Supported hosts:** Linux and macOS with Docker Engine or another Docker-compatible engine. Windows is supported through WSL2, treated as Linux.

## Consequences

- The Makefile and scripts are bash that runs on both Linux and macOS, so no GNU-only flags.
- `make doctor` checks installed tools against `versions.env` and installs nothing.
- Kubernetes is pinned one minor behind latest, because the ecosystem (ArgoCD, Crossplane, Kyverno, Istio) lags new releases.
- Docker group membership is root-equivalent on the host; recorded in `docs/security.md`.

## References

- k3d: [registries](https://k3d.io/stable/usage/registries/), [load balancer defaults](https://github.com/k3d-io/k3d/blob/main/docs/design/defaults.md)
- kind: [LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/), [local registry](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [ArgoCD tested Kubernetes versions](https://argo-cd.readthedocs.io/en/stable/operator-manual/tested-kubernetes-versions/)
