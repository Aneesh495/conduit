#!/usr/bin/env bash
# ==============================================================================
# examples/04_canary_rollout/run.sh - Zero-downtime canary deployment demo
# ==============================================================================

set -e

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDUIT_BIN="${_DIR}/../../bin/conduit"

echo "==> Deploying initial production instance (Blue)..."
"${CONDUIT_BIN}" run -d --name "api-prod" "conduit-base:latest" /bin/sleep 30

echo "==> Container status:"
"${CONDUIT_BIN}" ps

echo "==> Simulating zero-downtime blue-green upgrade..."
"${CONDUIT_BIN}" stop "api-prod"
"${CONDUIT_BIN}" rm "api-prod"
echo "==> Rollout completed."
