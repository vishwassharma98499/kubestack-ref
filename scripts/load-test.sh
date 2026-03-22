#!/usr/bin/env bash
# ──────────────────────────────────────────────
# load-test.sh — Generate traffic for demo dashboards
#
# Spins up a temporary pod inside the cluster and hammers
# the sample-api endpoints for 60 seconds. The traffic
# shows up in Grafana dashboards — great for live demos.
#
# Usage:
#   ./scripts/load-test.sh              # Default: 60 seconds
#   ./scripts/load-test.sh 120          # Custom duration
#   ./scripts/load-test.sh 60 20        # 60s, 20 concurrent workers
#
# No external tools required — uses wget inside the cluster.
# ──────────────────────────────────────────────
set -euo pipefail

DURATION="${1:-60}"
CONCURRENCY="${2:-10}"
NAMESPACE="app"
SERVICE="sample-api"
SERVICE_URL="http://${SERVICE}.${NAMESPACE}.svc.cluster.local"
TIMESTAMP="$(date +%s)"
POD_NAME="load-test-${TIMESTAMP}"
CM_NAME="load-test-script-${TIMESTAMP}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}[load-test]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Cleanup on exit
cleanup() {
  log "Cleaning up..."
  kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found --wait=false &>/dev/null || true
  kubectl delete configmap "${CM_NAME}" -n "${NAMESPACE}" --ignore-not-found &>/dev/null || true
}
trap cleanup EXIT INT TERM

log "Starting load test against ${SERVICE_URL}"
log "Duration: ${DURATION}s | Concurrency: ${CONCURRENCY} workers"
echo ""

# Verify the service exists
kubectl get svc "${SERVICE}" -n "${NAMESPACE}" &>/dev/null || {
  echo "Error: Service ${SERVICE} not found in namespace ${NAMESPACE}."
  echo "Make sure the demo stack is running: make demo"
  exit 1
}

# Write the load script to a temp file
SCRIPT_FILE="$(mktemp)"
cat > "${SCRIPT_FILE}" <<SCRIPT
#!/bin/sh
URL="${SERVICE_URL}"
END=\$((  \$(date +%s) + ${DURATION} ))
WORKERS=${CONCURRENCY}

worker() {
  id=\$1; ok=0; fail=0
  while [ \$(date +%s) -lt \$END ]; do
    for path in / /info /healthz; do
      if wget -qO /dev/null --timeout=5 "\${URL}\${path}" 2>/dev/null; then
        ok=\$((ok + 1))
      else
        fail=\$((fail + 1))
      fi
    done
    sleep 0.\$(( \$id % 3 ))
  done
  echo "Worker \$id: \$((ok + fail)) requests, \$ok ok, \$fail errors"
}

echo "=== Load Test Started ==="
echo "Target:   ${SERVICE_URL}"
echo "Duration: ${DURATION}s"
echo "Workers:  ${CONCURRENCY}"
echo "========================="
echo ""

i=1
while [ \$i -le \$WORKERS ]; do
  worker \$i &
  i=\$((i + 1))
done

wait

echo ""
echo "=== Load Test Complete ==="
SCRIPT

# Create ConfigMap from the script file
kubectl create configmap "${CM_NAME}" -n "${NAMESPACE}" \
  --from-file=run.sh="${SCRIPT_FILE}" &>/dev/null
rm -f "${SCRIPT_FILE}"
ok "ConfigMap created"

# Launch the pod with the script mounted
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: load-test
    team: platform
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 5
  containers:
    - name: load-test
      image: busybox:1.36
      command: ["sh", "/scripts/run.sh"]
      resources:
        requests:
          cpu: 50m
          memory: 32Mi
        limits:
          cpu: 200m
          memory: 64Mi
      volumeMounts:
        - name: script
          mountPath: /scripts
  volumes:
    - name: script
      configMap:
        name: ${CM_NAME}
        defaultMode: 0755
EOF

ok "Load-test pod created"

# Wait for pod to start
kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n "${NAMESPACE}" --timeout=30s &>/dev/null || {
  warn "Pod didn't reach Ready state — checking status..."
  kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}" | tail -15
  exit 1
}

log "Load test running for ${DURATION} seconds..."
echo ""
warn "Watch your Grafana dashboards: make port-forward-grafana → http://localhost:3000"
echo ""

# Stream logs from the load-test pod
kubectl logs -f "${POD_NAME}" -n "${NAMESPACE}" 2>/dev/null || true

# Wait for pod to complete
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${POD_NAME}" -n "${NAMESPACE}" --timeout=$((DURATION + 60))s &>/dev/null || {
  warn "Pod did not complete cleanly — check logs above"
}

echo ""
ok "Load test finished! Check Grafana for metrics."
log "Dashboards: make port-forward-grafana → http://localhost:3000"