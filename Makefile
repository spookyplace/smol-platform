include versions.env
export

CLUSTER := smol

.DEFAULT_GOAL := help

.PHONY: help doctor cluster cluster-down floci floci-down argocd argocd-password

FLOCI_COMPOSE := docker compose -f floci/compose.yaml
ARGOCD_CHART := argo-cd --repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART_VERSION)

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

doctor: ## Check installed tools against versions.env (installs nothing)
	@./scripts/doctor.sh

cluster: ## Create the k3d cluster (no-op if it exists)
	@test -n "$(K3S_IMAGE)" || { echo "K3S_IMAGE not set (versions.env)"; exit 1; }
	@if k3d cluster get $(CLUSTER) >/dev/null 2>&1; then \
	  echo "cluster '$(CLUSTER)' already exists"; \
	else \
	  k3d cluster create --config k3d/cluster.yaml; \
	fi

cluster-down: ## Delete the k3d cluster and its registry
	k3d cluster delete $(CLUSTER)

floci: cluster ## Start Floci on the cluster's network and wait until healthy
	$(FLOCI_COMPOSE) up -d --wait

floci-down: ## Stop and remove Floci (state is in memory, so it is lost)
	$(FLOCI_COMPOSE) down -v

argocd: cluster ## Install ArgoCD (Helm) and apply the root app; safe to re-run (ADR-0002)
	@grep -q 'targetRevision: $(ARGOCD_CHART_VERSION)$$' gitops/apps/argocd.yaml || \
	  { echo "gitops/apps/argocd.yaml chart version != ARGOCD_CHART_VERSION ($(ARGOCD_CHART_VERSION))"; exit 1; }
	@helm show chart $(ARGOCD_CHART) | grep -qx 'appVersion: v$(ARGOCD_VERSION)' || \
	  { echo "chart $(ARGOCD_CHART_VERSION) is not ArgoCD v$(ARGOCD_VERSION)"; exit 1; }
	helm upgrade --install argocd $(ARGOCD_CHART) \
	  --namespace argocd --create-namespace \
	  --values gitops/argocd/values.yaml --wait --timeout 5m
	kubectl apply -f gitops/root.yaml

argocd-password: ## Print the initial admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
