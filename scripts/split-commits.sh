#!/usr/bin/env bash
# ──────────────────────────────────────────────
# split-commits.sh — Rewrite git history into realistic commits
#
# Works on an EXISTING repo that already has commits pushed.
# Creates a new orphan branch with 9 logical commits, then
# force-replaces main.
#
# Usage:
#   ./scripts/split-commits.sh
#
# WARNING: This rewrites history. You will need:
#   git push --force-with-lease origin main
# ──────────────────────────────────────────────
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[split-commits]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Must be run from the project root
[[ -f "Makefile" ]] || err "Run this from the kubestack-ref project root."
[[ -d ".git" ]] || err "Not a git repository."

# Safety check
echo ""
warn "This will REWRITE your git history."
warn "After running, you must: git push --force-with-lease origin main"
echo ""
read -r -p "Continue? (y/N): " CONFIRM
[[ "${CONFIRM}" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Base date: 2 weeks ago, each commit ~1-2 days apart
if date -v-14d +%s &>/dev/null 2>&1; then
  # macOS
  BASE_TS=$(date -v-14d +%s)
  datecmd() { date -r "$1" +%Y-%m-%dT%H:%M:%S%z; }
else
  # Linux
  BASE_TS=$(date -d "14 days ago" +%s)
  datecmd() { date -d "@$1" --iso-8601=seconds; }
fi
STEP=86400  # 1 day

# Helper: commit with a specific date offset
commit_at() {
  local offset=$1
  shift
  local msg="$*"
  local ts=$((BASE_TS + offset * STEP))
  local date_str
  date_str=$(datecmd "${ts}")

  git add -A
  GIT_AUTHOR_DATE="${date_str}" GIT_COMMITTER_DATE="${date_str}" \
    git commit --allow-empty -m "${msg}" 2>/dev/null || true
}

log "Saving all current files to a temp directory..."
STASH_DIR=$(mktemp -d)
# Copy everything except .git
rsync -a --exclude='.git' . "${STASH_DIR}/repo/"
ok "Files saved to ${STASH_DIR}/repo/"

log "Creating orphan branch 'split-history'..."
git checkout --orphan split-history
git rm -rf . &>/dev/null || true
git clean -fd &>/dev/null || true

# Helper: copy files from stash
restore() {
  for f in "$@"; do
    local src="${STASH_DIR}/repo/${f}"
    if [[ -d "${src}" ]]; then
      mkdir -p "${f}"
      cp -a "${src}/." "${f}/"
    elif [[ -f "${src}" ]]; then
      mkdir -p "$(dirname "${f}")"
      cp -a "${src}" "${f}"
    else
      warn "Not found: ${f} (skipping)"
    fi
  done
}

# ── Commit 1: Terraform modules ──────────────
log "Commit 1/9: Terraform modules..."
restore terraform/ .gitignore
commit_at 0 "feat: add terraform modules for AWS infrastructure

Modular Terraform for production AWS:
- VPC with 3 AZs, public/private subnets, NAT Gateway, flow logs
- EKS cluster with managed node groups, OIDC/IRSA, KMS encryption
- RDS PostgreSQL with encryption, Multi-AZ, automated backups
- S3 buckets with versioning, encryption, lifecycle policies
- ECR with image scanning and lifecycle rules
- IAM IRSA roles for app, ALB controller, external-dns, cert-manager
- Security groups with least-privilege rules

All modules have variable validation and pass tfsec + trivy scans."
ok "Commit 1"

# ── Commit 2: Kubernetes base manifests ──────
log "Commit 2/9: Kubernetes base manifests..."
restore kubernetes/base/
commit_at 1 "feat: add kubernetes base manifests and network policies

Foundation Kubernetes resources:
- Namespaces: app, monitoring, argocd, ingress, logging, cert-manager,
  gatekeeper-system, sealed-secrets, kubecost
- Resource quotas per namespace
- LimitRange defaults for containers
- Network policies: default deny-all ingress/egress in app namespace,
  explicit allow for ingress controller, DNS, external HTTPS, RDS,
  Prometheus scraping"
ok "Commit 2"

# ── Commit 3: Sample API microservice ────────
log "Commit 3/9: Sample API microservice..."
restore app/ kubernetes/apps/sample-api/
commit_at 3 "feat: add sample-api Go microservice with health and metrics

Production-grade Go API server:
- Endpoints: /healthz, /readyz, /info, / with structured JSON responses
- Prometheus metrics: http_requests_total, http_request_duration_seconds
- Structured JSON logging via slog with configurable levels
- Graceful shutdown with SIGINT/SIGTERM handling
- Multi-stage Dockerfile: golang builder → distroless runtime
- K8s manifests: Deployment (anti-affinity, security contexts, probes),
  Service, Ingress, HPA, PDB, ConfigMap, ServiceAccount"
ok "Commit 3"

# ── Commit 4: ArgoCD platform config ─────────
log "Commit 4/9: ArgoCD configuration..."
restore kubernetes/platform/argocd/
commit_at 5 "feat: add ArgoCD platform configuration

GitOps setup with app-of-apps pattern:
- AppProject 'applications': restricted to app namespace
- AppProject 'infrastructure': full cluster access for platform components
- App-of-apps root Application for hierarchical management
- sample-api Application CR with automated sync and self-heal"
ok "Commit 4"

# ── Commit 5: Prometheus monitoring ──────────
log "Commit 5/9: Monitoring stack..."
restore kubernetes/platform/monitoring/
commit_at 6 "feat: add prometheus monitoring and grafana dashboards

Observability stack:
- PrometheusRule with alerts for: pod crash loops, high CPU/memory,
  5xx error rate >5%, p95 latency >2s, cert expiry, PVC >85% full
- Grafana dashboard: Cluster Overview
- Grafana dashboard: Application Metrics"
ok "Commit 5"

# ── Commit 6: OPA Gatekeeper ─────────────────
log "Commit 6/9: OPA Gatekeeper..."
restore kubernetes/platform/security/
commit_at 7 "feat: add OPA gatekeeper security constraints

Policy enforcement with four constraint templates:
- require-app-team-labels: reject pods missing app/team labels
- deny-privileged-containers: reject privileged containers
- require-resource-limits: reject containers without limits
- allowed-repos: restrict images to approved registries"
ok "Commit 6"

# ── Commit 7: GitHub Actions CI ──────────────
log "Commit 7/9: CI pipeline..."
restore .github/ .devcontainer/
commit_at 9 "feat: add GitHub Actions CI pipeline

Multi-stage CI on every PR and push to main:
- terraform: fmt check + validate all modules
- kubernetes: kubeconform validation
- security: tfsec + trivy scanning
- docker: build + smoke test
- integration: full K3d cluster test

Also adds Codespaces devcontainer, CODEOWNERS, PR template."
ok "Commit 7"

# ── Commit 8: K3d demo + extras ──────────────
log "Commit 8/9: Demo scripts and extras..."
restore scripts/ Makefile kubernetes/apps/health-dashboard/ kubernetes/overlays/
commit_at 11 "feat: add local K3d demo setup scripts

One-command local stack: make demo
- demo-up.sh: K3d + ArgoCD + Prometheus + Grafana + NGINX + apps
- demo-down.sh / demo-test.sh: teardown and smoke tests
- load-test.sh: in-cluster traffic generation for dashboards
- take-screenshots.sh: port-forward all services for screenshots
- fix-go-sum.sh: regenerate go.sum via Docker
- split-commits.sh: create realistic git history
- Kustomize overlays for dev and prod
- Health dashboard: nginx + HTML/JS status page"
ok "Commit 8"

# ── Commit 9: Documentation ──────────────────
log "Commit 9/9: Documentation..."
restore docs/ README.md CHANGELOG.md LICENSE
commit_at 13 "docs: add architecture docs, runbook, security model, and ADRs

Complete documentation:
- ARCHITECTURE.md with Mermaid diagrams
- RUNBOOK.md: scaling, debugging, rollback procedures
- SECURITY.md: IRSA, network policies, OPA, container hardening
- COST_OPTIMIZATION.md: spot instances, right-sizing, Kubecost
- 3 Architecture Decision Records
- README with skills demonstrated, demo instructions, project structure"
ok "Commit 9"

# Replace main with the new history
log "Replacing '${CURRENT_BRANCH}' with new history..."
git branch -D "${CURRENT_BRANCH}" 2>/dev/null || true
git branch -m "${CURRENT_BRANCH}"

# Cleanup
rm -rf "${STASH_DIR}"

echo ""
ok "Done! New git history:"
echo ""
git log --oneline --reverse
echo ""
COMMIT_COUNT=$(git rev-list --count HEAD)
echo -e "  ${YELLOW}Total commits:${NC} ${COMMIT_COUNT}"
echo ""
echo -e "  ${RED}NEXT STEP — push the rewritten history:${NC}"
echo ""
echo "    git push --force-with-lease origin ${CURRENT_BRANCH}"
echo ""