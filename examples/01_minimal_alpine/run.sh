#!/usr/bin/env bash
# ==============================================================================
# examples/01_minimal_alpine/run.sh - Run baseline container workload
# ==============================================================================

set -e

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDUIT_BIN="${_DIR}/../../bin/conduit"

echo "==> Running baseline container..."
"${CONDUIT_BIN}" run --name "baseline-demo" "conduit-base:latest" /bin/hello
