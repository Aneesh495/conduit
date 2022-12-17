#!/usr/bin/env bash
# ==============================================================================
# examples/02_web_stack/run.sh - Deploy and teardown multi-service web stack
# ==============================================================================

set -e

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDUIT_BIN="${_DIR}/../../bin/conduit"

cd "${_DIR}"

echo "==> Deploying multi-tier stack with Conduit Compose..."
"${CONDUIT_BIN}" compose up

echo "==> Current active containers:"
"${CONDUIT_BIN}" ps

echo "==> Tearing down multi-tier stack..."
"${CONDUIT_BIN}" compose down
