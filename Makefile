include versions.env
export

CLUSTER := smol

.DEFAULT_GOAL := help

.PHONY: help doctor cluster cluster-down floci floci-down

FLOCI_COMPOSE := docker compose -f floci/compose.yaml

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

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
