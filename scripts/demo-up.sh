#!/usr/bin/env bash
set -euo pipefail
CLUSTER_NAME="kubestack-ref"
APP_IMAGE="kubestack-ref/sample-api:local"
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[kubestack-ref]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

log "Preflight checks..."
command -v docker &>/dev/null || err "Docker required: https://docs.docker.com/get-docker/"
docker info &>/dev/null || err "Docker daemon not running"
if ! command -v k3d &>/dev/null; then
  warn "Installing k3d..."
  curl -sL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.6.3 bash
fi
if ! command -v kubectl &>/dev/null; then
  warn "Installing kubectl..."
  curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi
if ! command -v helm &>/dev/null; then
  warn "Installing helm..."
  curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
ok "Prerequisites satisfied"

if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  warn "Cluster '${CLUSTER_NAME}' exists, reusing"
else
  log "Creating K3d cluster..."
  k3d cluster create "${CLUSTER_NAME}" --servers 1 --agents 2 \
    --port "8080:80@loadbalancer" --port "8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" --wait --timeout 120s
  ok "Cluster created"
fi
kubectl config use-context "k3d-${CLUSTER_NAME}"

log "Building app images..."
docker build -t "${APP_IMAGE}" ./app/
DASHBOARD_IMAGE="kubestack-ref/health-dashboard:local"
docker build -t "${DASHBOARD_IMAGE}" ./kubernetes/apps/health-dashboard/
k3d image import "${APP_IMAGE}" "${DASHBOARD_IMAGE}" -c "${CLUSTER_NAME}"
ok "Images imported"

log "Creating namespaces..."
kubectl apply -f kubernetes/base/namespace.yaml

log "Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.service.type=ClusterIP --set 'server.extraArgs={--insecure}' \
  --set controller.replicas=1 --set repoServer.replicas=1 \
  --set applicationSet.replicas=1 --set redis-ha.enabled=false \
  --set configs.cm."admin\.enabled"="true" --wait --timeout 300s
ok "ArgoCD installed"

log "Installing Prometheus + Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=6h \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set grafana.adminPassword=kubestack-ref \
  --set grafana.resources.requests.cpu=50m \
  --set grafana.resources.requests.memory=128Mi \
  --set alertmanager.enabled=false --wait --timeout 300s
ok "Prometheus + Grafana installed"

log "Installing NGINX Ingress..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress --create-namespace \
  --set controller.resources.requests.cpu=50m --set controller.resources.requests.memory=64Mi \
  --set controller.service.type=ClusterIP --set controller.watchIngressWithoutClass=true \
  --wait --timeout 180s
ok "Ingress installed"

log "Deploying base resources + app..."
kubectl apply -f kubernetes/base/resource-quotas.yaml
kubectl apply -f kubernetes/base/limit-ranges.yaml
kubectl apply -f kubernetes/apps/sample-api/
ok "App deployed"

log "Waiting for sample-api..."
kubectl wait --for=condition=available deployment/sample-api -n app --timeout=120s
ok "sample-api ready"

log "Configuring ArgoCD Applications..."
kubectl apply -f kubernetes/platform/argocd/projects/ 2>/dev/null || true
kubectl apply -f kubernetes/platform/argocd/apps/sample-api.yaml 2>/dev/null || true
kubectl apply -f kubernetes/platform/argocd/app-of-apps.yaml 2>/dev/null || true
ok "ArgoCD Applications configured (visible in ArgoCD UI)"

log "Deploying health-dashboard..."
kubectl apply -f kubernetes/apps/health-dashboard/ 2>/dev/null || true
kubectl wait --for=condition=available deployment/health-dashboard -n app --timeout=60s 2>/dev/null || warn "health-dashboard not ready yet (may need image pull)"
ok "Health dashboard deployed"

log "Importing Grafana dashboards..."
kubectl create configmap grafana-dashboard-cluster --from-file=cluster-overview.json=kubernetes/platform/monitoring/grafana-dashboards/cluster-overview.json -n monitoring --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client | kubectl apply -f -
kubectl create configmap grafana-dashboard-app --from-file=application.json=kubernetes/platform/monitoring/grafana-dashboards/application.json -n monitoring --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml --dry-run=client | kubectl apply -f -
kubectl apply -f kubernetes/platform/monitoring/alerting-rules.yaml
ok "Dashboards imported"

ARGOCD_PW=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "admin")
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  kubestack-ref — Local Stack Running!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}Sample API:${NC}       make port-forward-api       → http://localhost:8080"
echo -e "  ${BLUE}Health Dashboard:${NC} make port-forward-dashboard → http://localhost:8081"
echo -e "  ${BLUE}ArgoCD UI:${NC}        make port-forward-argocd    → https://localhost:9080  (admin / ${ARGOCD_PW})"
echo -e "  ${BLUE}Grafana:${NC}          make port-forward-grafana   → http://localhost:3000   (admin / kubestack-ref)"
echo -e "  ${BLUE}Prometheus:${NC}       make port-forward-prometheus → http://localhost:9090"
echo ""
echo -e "  ${RED}Tear down:${NC}  make demo-down"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
