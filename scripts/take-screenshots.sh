#!/usr/bin/env bash
# ──────────────────────────────────────────────
# take-screenshots.sh — Port-forward all services for screenshots
#
# Opens all the port-forwards you need to take screenshots
# of the running stack for the README. Prints URLs and
# credentials, then waits for you to press Enter to tear down.
#
# Usage:
#   ./scripts/take-screenshots.sh
#
# All port-forward processes are cleaned up on exit (Ctrl+C or Enter).
# ──────────────────────────────────────────────
set -euo pipefail

PIDS=()
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${BLUE}[screenshots]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Kill all port-forward processes on exit
cleanup() {
  echo ""
  log "Stopping all port-forwards..."
  for pid in "${PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  ok "All port-forwards stopped."
}
trap cleanup EXIT INT TERM

# Verify cluster is running
kubectl cluster-info &>/dev/null || {
  echo -e "${RED}[✗]${NC} Cannot connect to the cluster. Run 'make demo' first."
  exit 1
}

log "Starting port-forwards for all services..."
echo ""

# ── Sample API ────────────────────────────────
kubectl port-forward svc/sample-api -n app 8080:80 &>/dev/null &
PIDS+=($!)
ok "Sample API       → http://localhost:8080"

# ── ArgoCD ────────────────────────────────────
kubectl port-forward svc/argocd-server -n argocd 9080:443 &>/dev/null &
PIDS+=($!)
ARGOCD_PW=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
ok "ArgoCD UI        → https://localhost:9080"

# ── Grafana ───────────────────────────────────
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80 &>/dev/null &
PIDS+=($!)
ok "Grafana          → http://localhost:3000"

# ── Prometheus ────────────────────────────────
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090 &>/dev/null &
PIDS+=($!)
ok "Prometheus       → http://localhost:9090"

# Give port-forwards a moment to establish
sleep 2

# Verify they're actually working
FAILED=0
for pid in "${PIDS[@]}"; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    ((FAILED++))
  fi
done
if [[ ${FAILED} -gt 0 ]]; then
  warn "${FAILED} port-forward(s) may have failed — some services might not be running"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  All services are port-forwarded — take your screenshots!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Sample API:${NC}"
echo "    URL:   http://localhost:8080"
echo "    Try:   curl http://localhost:8080/healthz | jq ."
echo "    Try:   curl http://localhost:8080/info | jq ."
echo ""
echo -e "  ${BOLD}ArgoCD:${NC}"
echo "    URL:   https://localhost:9080  (accept self-signed cert)"
echo "    User:  admin"
echo "    Pass:  ${ARGOCD_PW}"
echo ""
echo -e "  ${BOLD}Grafana:${NC}"
echo "    URL:   http://localhost:3000"
echo "    User:  admin"
echo "    Pass:  kubestack-ref"
echo "    Dashboards: Search for 'Kubestack-Ref'"
echo ""
echo -e "  ${BOLD}Prometheus:${NC}"
echo "    URL:   http://localhost:9090"
echo "    Try query: http_requests_total"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Tip:${NC} Run the load test in another terminal to generate metrics:"
echo "       ./scripts/load-test.sh 30"
echo ""
echo -e "  ${YELLOW}Tip:${NC} Record a terminal demo with asciinema:"
echo "       asciinema rec demo.cast"
echo "       # ... run make demo, make demo-test, etc."
echo "       asciinema upload demo.cast"
echo ""
echo -e "  ${YELLOW}Tip:${NC} Record a GIF with VHS (https://github.com/charmbracelet/vhs):"
echo "       vhs scripts/demo.tape"
echo ""

read -r -p "Press Enter to stop all port-forwards and exit..."
