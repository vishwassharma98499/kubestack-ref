.PHONY: help demo demo-down demo-test build run-local port-forward-api port-forward-argocd port-forward-grafana port-forward-prometheus lint scan fmt validate docs clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ── Local Demo (K3d) ────────────────────────────
demo: ## 🚀 One command: full local K8s stack (K3d + ArgoCD + Prometheus + Grafana + app)
	@chmod +x scripts/*.sh && ./scripts/demo-up.sh

demo-down: ## 💥 Tear down the entire local stack
	@./scripts/demo-down.sh

demo-test: ## ✅ Run smoke tests against the local stack
	@./scripts/demo-test.sh

# ── Port Forwarding ─────────────────────────────
port-forward-api: ## Forward sample-api → localhost:8080
	@echo "→ http://localhost:8080 — Ctrl+C to stop"
	@kubectl port-forward svc/sample-api -n app 8080:80

port-forward-dashboard: ## Forward health-dashboard → localhost:8081
	@echo "→ http://localhost:8081 — Ctrl+C to stop"
	@kubectl port-forward svc/health-dashboard -n app 8081:80

port-forward-argocd: ## Forward ArgoCD → localhost:9080
	@echo "→ https://localhost:9080 — admin / $$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"
	@kubectl port-forward svc/argocd-server -n argocd 9080:443

port-forward-grafana: ## Forward Grafana → localhost:3000
	@echo "→ http://localhost:3000 — admin / kubestack-ref"
	@kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

port-forward-prometheus: ## Forward Prometheus → localhost:9090
	@kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090

# ── Docker ──────────────────────────────────────
build: ## Build sample-api Docker image
	docker build -t kubestack-ref/sample-api:local ./app/

run-local: build ## Run sample-api standalone in Docker
	docker run --rm -p 8080:8080 -p 9090:9090 -e APP_ENV=local -e LOG_LEVEL=debug kubestack-ref/sample-api:local

# ── Terraform ───────────────────────────────────
fmt: ## Format Terraform files
	terraform fmt -recursive terraform/

validate: ## Validate Terraform modules
	@for dir in terraform/modules/*/; do echo "==> $$dir"; cd "$$dir" && terraform init -backend=false -input=false >/dev/null 2>&1 && terraform validate && cd - >/dev/null; done

# ── Linting & Security ──────────────────────────
lint: ## Lint all Terraform + K8s manifests
	@echo "==> Terraform fmt check..." && terraform fmt -check -recursive terraform/ || (echo "Run 'make fmt'"; exit 1)
	@echo "==> K8s validation..." && if command -v kubeconform >/dev/null; then find kubernetes/ -name '*.yaml' -not -path '*/grafana-dashboards/*' | xargs kubeconform -strict -ignore-missing-schemas; else echo "kubeconform not installed"; fi

scan: ## Security scan (tfsec + trivy)
	@tfsec terraform/ 2>/dev/null || echo "(install tfsec)"
	@trivy config terraform/ 2>/dev/null || echo "(install trivy)"
	@trivy config kubernetes/ 2>/dev/null || true

# ── Docs ────────────────────────────────────────
docs: ## Generate Terraform module docs
	@if command -v terraform-docs >/dev/null; then for dir in terraform/modules/*/; do terraform-docs markdown table "$$dir" > "$$dir/README.md"; done; fi

clean: ## Remove temp files
	find terraform/ -name '.terraform' -type d -exec rm -rf {} + 2>/dev/null || true
	find terraform/ -name '*.tfplan' -delete 2>/dev/null || true

# ── Extras ──────────────────────────────────────
load-test: ## 📈 Generate traffic for Grafana dashboards (60s default)
	@chmod +x scripts/load-test.sh && ./scripts/load-test.sh $(or $(DURATION),60) $(or $(CONCURRENCY),10)

screenshots: ## 📸 Port-forward all services for taking screenshots
	@chmod +x scripts/take-screenshots.sh && ./scripts/take-screenshots.sh

fix-go-sum: ## 🔧 Regenerate app/go.sum with real hashes (requires Docker)
	@chmod +x scripts/fix-go-sum.sh && ./scripts/fix-go-sum.sh

split-commits: ## 🔀 Split initial commit into realistic git history
	@chmod +x scripts/split-commits.sh && ./scripts/split-commits.sh
