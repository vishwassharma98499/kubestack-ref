#!/usr/bin/env bash
# ──────────────────────────────────────────────
# fix-go-sum.sh — Regenerate app/go.sum with real hashes
#
# The committed go.sum has placeholder hashes. This script
# runs `go mod tidy` inside a Docker container to produce
# a correct go.sum that matches the imports in main.go.
#
# Usage:
#   ./scripts/fix-go-sum.sh
#
# Requirements: Docker
# ──────────────────────────────────────────────
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}[fix-go-sum]${NC} $1"; }
ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Resolve project root (works when called from any directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/app"

command -v docker &>/dev/null || err "Docker is required but not installed."
docker info &>/dev/null 2>&1 || err "Docker daemon is not running."

[[ -f "${APP_DIR}/go.mod" ]] || err "go.mod not found at ${APP_DIR}/go.mod"

log "Backing up current go.sum..."
if [[ -f "${APP_DIR}/go.sum" ]]; then
  cp "${APP_DIR}/go.sum" "${APP_DIR}/go.sum.bak"
fi

log "Running 'go mod tidy' in golang:1.22-alpine container..."
docker run --rm \
  -v "${APP_DIR}:/app" \
  -w /app \
  -e GOFLAGS="-mod=mod" \
  golang:1.22-alpine \
  sh -c "go mod tidy && echo 'go mod tidy completed successfully'"

if [[ -f "${APP_DIR}/go.sum" ]]; then
  LINES=$(wc -l < "${APP_DIR}/go.sum")
  ok "go.sum regenerated (${LINES} lines)"
  
  # Verify the hashes look real (not placeholder)
  if grep -q "h1:" "${APP_DIR}/go.sum"; then
    ok "Hashes look valid"
  else
    err "go.sum does not contain valid hashes — something went wrong"
  fi
else
  err "go.sum was not generated"
fi

# Clean up backup if everything succeeded
rm -f "${APP_DIR}/go.sum.bak"

log "Done! You can verify with:"
echo "  docker run --rm -v ${APP_DIR}:/app -w /app golang:1.22-alpine go mod verify"
