#!/usr/bin/env bash
set -euo pipefail
echo "[kubestack-ref] Deleting K3d cluster..."
k3d cluster delete kubestack-ref 2>/dev/null || true
docker image rm kubestack-ref/sample-api:local 2>/dev/null || true
echo "[✓] Stack torn down."
