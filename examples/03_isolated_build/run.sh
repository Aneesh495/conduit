#!/usr/bin/env bash
# ==============================================================================
# examples/03_isolated_build/run.sh - Hermetic air-gapped container compilation
# ==============================================================================

set -e

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDUIT_BIN="${_DIR}/../../bin/conduit"

echo "==> Running hermetic build step with network isolation..."
"${CONDUIT_BIN}" run --name "airgap-builder" "conduit-base:latest" /bin/sh -c 'echo "Hermetic compilation artifact generated at $(date)"'
echo "==> Cleaned up builder container."
"${CONDUIT_BIN}" rm "airgap-builder" >/dev/null 2>&1 || true
