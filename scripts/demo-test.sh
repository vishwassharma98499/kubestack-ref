#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
check() { local n="$1"; shift; if "$@" &>/dev/null; then echo -e "  ${GREEN}✓${NC} ${n}"; PASS=$((PASS+1)); else echo -e "  ${RED}✗${NC} ${n}"; FAIL=$((FAIL+1)); fi; }

echo ""; echo "══════════════════════════════════════"; echo "  kubestack-ref — Smoke Tests"; echo "══════════════════════════════════════"; echo ""

echo "Cluster:"
check "K3d cluster exists" k3d cluster list
check "kubectl connected" kubectl cluster-info
check "Nodes ready" kubectl get nodes

echo ""; echo "Namespaces:"
for ns in app monitoring argocd ingress; do check "Namespace '${ns}'" kubectl get namespace "${ns}"; done

echo ""; echo "Workloads:"
check "sample-api ready" kubectl rollout status deployment/sample-api -n app --timeout=10s
check "ArgoCD server" kubectl rollout status deployment/argocd-server -n argocd --timeout=10s
check "Prometheus" kubectl get statefulset -n monitoring -l app.kubernetes.io/name=prometheus
check "Grafana" kubectl rollout status deployment/prometheus-grafana -n monitoring --timeout=10s

echo ""; echo "API endpoints:"
check "GET /healthz" kubectl run healthz-test --rm -i --image=curlimages/curl --restart=Never -n app -- curl -sf http://sample-api.app.svc:80/healthz
check "GET /info" kubectl run info-test --rm -i --image=curlimages/curl --restart=Never -n app -- curl -sf http://sample-api.app.svc:80/info
check "GET /metrics" kubectl run metrics-test --rm -i --image=curlimages/curl --restart=Never -n app -- curl -sf http://sample-api.app.svc:9090/metrics

echo ""; echo "K8s resources:"
check "HPA" kubectl get hpa sample-api -n app
check "PDB" kubectl get pdb sample-api -n app
check "ConfigMap" kubectl get configmap sample-api-config -n app
check "ServiceAccount" kubectl get serviceaccount sample-api -n app

echo ""; echo "══════════════════════════════════════"
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "══════════════════════════════════════"
[ ${FAIL} -eq 0 ]
