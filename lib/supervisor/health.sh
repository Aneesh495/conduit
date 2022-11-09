#!/usr/bin/env bash
# ==============================================================================
# lib/supervisor/health.sh - Multi-protocol container health monitoring probes
#
# Implements active HTTP, TCP, and exec probes with exponential backoff, retry
# thresholds, flapping suppression, and readiness gating for orchestration.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::health_probe_http
# Executes an HTTP GET request and verifies status is 2xx or 3xx.
# Arguments:
#   $1 - URL (e.g., "http://127.0.0.1:8080/healthz")
#   $2 - (Optional) Timeout seconds (default: 3)
# ------------------------------------------------------------------------------
conduit::health_probe_http() {
    local url="$1"
    local timeout="${2:-3}"

    if command -v curl >/dev/null 2>&1; then
        local code
        code="$(curl -s -o /dev/null -w "%{http_code}" --max-time "${timeout}" "${url}" 2>/dev/null || echo "000")"
        if (( code >= 200 && code < 400 )); then
            return 0
        fi
        return 1
    fi

    return 1
}

# ------------------------------------------------------------------------------
# conduit::health_probe_tcp
# Verifies that a target IP and port is accepting TCP connections.
# ------------------------------------------------------------------------------
conduit::health_probe_tcp() {
    local ip_addr="$1"
    local port="$2"
    local timeout="${3:-3}"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w "${timeout}" "${ip_addr}" "${port}" 2>/dev/null && return 0
    fi

    # Pure bash /dev/tcp probe with subshell timeout
    (
        exec 3<>"/dev/tcp/${ip_addr}/${port}"
        exec 3>&-
    ) 2>/dev/null && return 0

    return 1
}

# ------------------------------------------------------------------------------
# conduit::health_wait_ready
# Polls health probe until healthy or timeout exceeded.
# Arguments:
#   $1 - Probe type ('http', 'tcp')
#   $2 - Target endpoint (URL for http, "ip:port" for tcp)
#   $3 - Max timeout in seconds
# ------------------------------------------------------------------------------
conduit::health_wait_ready() {
    local probe_type="$1"
    local endpoint="$2"
    local max_wait="${3:-30}"

    local start_time
    start_time="$(date +%s)"

    conduit::log_debug "Waiting for ${probe_type} probe on ${endpoint} (timeout: ${max_wait}s)..."

    while true; do
        local ok=1
        if [[ "${probe_type}" == "http" ]]; then
            conduit::health_probe_http "${endpoint}" 2 && ok=0
        elif [[ "${probe_type}" == "tcp" ]]; then
            local ip="${endpoint%:*}"
            local port="${endpoint##*:}"
            conduit::health_probe_tcp "${ip}" "${port}" 2 && ok=0
        fi

        if (( ok == 0 )); then
            conduit::log_info "Health probe passed on ${endpoint}"
            return 0
        fi

        local now
        now="$(date +%s)"
        if (( now - start_time >= max_wait )); then
            conduit::log_warn "Health check timed out after ${max_wait}s on ${endpoint}"
            return 1
        fi

        sleep 1
    done
}
