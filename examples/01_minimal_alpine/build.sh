#!/usr/bin/env bash
# ==============================================================================
# examples/01_minimal_alpine/build.sh - Build a lightweight baseline image
# ==============================================================================

set -e

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDUIT_BIN="${_DIR}/../../bin/conduit"

BUILD_CTX="${_DIR}/context"
mkdir -p "${BUILD_CTX}/bin" "${BUILD_CTX}/etc"

cat <<'EOF' > "${BUILD_CTX}/bin/hello"
#!/bin/sh
echo "=== Conduit Baseline Container Runtime Environment ==="
echo "Host OS: $(uname -s)"
echo "Date:    $(date)"
echo "Process: PID $$"
echo "======================================================="
EOF
chmod +x "${BUILD_CTX}/bin/hello"

echo "NAME=conduit-minimal" > "${BUILD_CTX}/etc/os-release"

"${CONDUIT_BIN}" build -t "conduit-base:latest" "${BUILD_CTX}"
echo "==> Successfully built conduit-base:latest"
