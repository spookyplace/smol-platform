include versions.env
# Machine-specific values and paths to secret files; optional so `make help`/`doctor` work without it
-include local.env
export

CLUSTER := smol
# Every kubectl/helm call names this context, so a different current context (say, a work cluster) is never touched
KUBE_CONTEXT := k3d-$(CLUSTER)

.DEFAULT_GOAL := help
# Targets depend on order (doctor before cluster, Floci before the cluster is deleted); never run them in parallel
.NOTPARALLEL:

.PHONY: help up down doctor check-pins cluster cluster-down floci floci-down argocd argocd-password backstage-secrets

FLOCI_COMPOSE := docker compose -f floci/compose.yaml
# Chart pins repeated in gitops/apps/<app>.yaml, because ArgoCD can't read versions.env. Pairs of app:VARIABLE.
PINNED_APPS := argocd:ARGOCD_CHART_VERSION cloudnative-pg:CNPG_CHART_VERSION backstage:BACKSTAGE_CHART_VERSION
pin_app = $(word 1,$(subst :, ,$1))
pin_var = $(word 2,$(subst :, ,$1))
ARGOCD_CHART := argo-cd --repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART_VERSION)

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-19s %s\n", $$1, $$2}'

up: doctor floci argocd backstage-secrets ## Bring up everything: checks, cluster, Floci, ArgoCD, secrets (safe to re-run)
	@echo
	@echo "Smol is up. ArgoCD UI:"
	@echo "  kubectl --context $(KUBE_CONTEXT) -n argocd port-forward svc/argocd-server 8081:443"
	@echo "  https://localhost:8081  user: admin  password: make argocd-password"

down: floci-down cluster-down ## Remove everything (Floci first: it is attached to the cluster's network)

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

check-pins: ## Check chart versions in gitops/apps/ match versions.env
	@$(foreach p,$(PINNED_APPS),\
	  grep -q 'targetRevision: $($(call pin_var,$p))$$' gitops/apps/$(call pin_app,$p).yaml || \
	  { echo "gitops/apps/$(call pin_app,$p).yaml: chart version is not $(call pin_var,$p) ($($(call pin_var,$p)))"; exit 1; };)

argocd: cluster check-pins ## Install ArgoCD (Helm) and apply the root app; safe to re-run (ADR-0002)
	@helm show chart $(ARGOCD_CHART) | grep -qx 'appVersion: v$(ARGOCD_VERSION)' || \
	  { echo "chart $(ARGOCD_CHART_VERSION) is not ArgoCD v$(ARGOCD_VERSION)"; exit 1; }
	helm upgrade --install argocd $(ARGOCD_CHART) --kube-context $(KUBE_CONTEXT) \
	  --namespace argocd --create-namespace \
	  --values gitops/argocd/values.yaml --wait --timeout 5m
	kubectl --context $(KUBE_CONTEXT) apply -f gitops/apps/root.yaml

argocd-password: ## Print the initial admin password
	@kubectl --context $(KUBE_CONTEXT) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# Secrets never come from git (O6). Built from files named in local.env: --from-file, so secret values
# never appear in process arguments. Server-side apply, so no last-applied annotation copies the data.
backstage-secrets: cluster ## Create the Backstage GitHub App Secret from local.env (ADR-0003)
	@test -f local.env || { echo "local.env missing: copy local.env.example and fill it in"; exit 1; }
	@test -n "$(GITHUB_APP_ID)" -a -n "$(GITHUB_APP_CLIENT_ID)" || \
	  { echo "local.env: GITHUB_APP_ID and GITHUB_APP_CLIENT_ID must be set"; exit 1; }
	@test -r "$(GITHUB_APP_PRIVATE_KEY_FILE)" -a -r "$(GITHUB_APP_CLIENT_SECRET_FILE)" || \
	  { echo "local.env: GITHUB_APP_PRIVATE_KEY_FILE and GITHUB_APP_CLIENT_SECRET_FILE must be readable files"; exit 1; }
	@# --from-file copies bytes exactly; a trailing newline would become part of the OAuth client secret
	@! tail -c1 "$(GITHUB_APP_CLIENT_SECRET_FILE)" | od -An -tx1 | grep -q 0a || \
	  { echo "$(GITHUB_APP_CLIENT_SECRET_FILE) ends with a newline; remove it: truncate -s -1 $(GITHUB_APP_CLIENT_SECRET_FILE)"; exit 1; }
	@kubectl --context $(KUBE_CONTEXT) create namespace backstage --dry-run=client -o yaml | \
	  kubectl --context $(KUBE_CONTEXT) apply --server-side --field-manager=make -f - >/dev/null
	@kubectl --context $(KUBE_CONTEXT) -n backstage create secret generic backstage-github-app \
	  --from-literal=GITHUB_APP_ID=$(GITHUB_APP_ID) \
	  --from-literal=GITHUB_APP_CLIENT_ID=$(GITHUB_APP_CLIENT_ID) \
	  --from-file=GITHUB_APP_PRIVATE_KEY=$(GITHUB_APP_PRIVATE_KEY_FILE) \
	  --from-file=GITHUB_APP_CLIENT_SECRET=$(GITHUB_APP_CLIENT_SECRET_FILE) \
	  --dry-run=client -o yaml | \
	  kubectl --context $(KUBE_CONTEXT) apply --server-side --field-manager=make -f -
