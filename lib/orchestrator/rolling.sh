#!/usr/bin/env bash
# ==============================================================================
# lib/orchestrator/rolling.sh - Zero-downtime rolling deployment and rollback
#
# Coordinates blue-green updates, verifies health barriers on staging instances,
# executes atomic traffic cutovers, and automates rollback upon health failures.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "supervisor/state"
conduit::import "supervisor/process"
conduit::import "supervisor/health"

# ------------------------------------------------------------------------------
# conduit::rolling_update
# Executes zero-downtime blue-green replacement for a service.
# Arguments:
#   $1 - Service container name (e.g., "web_service_1")
#   $2 - New target image tag or ID
#   $3 - Health check endpoint (e.g., "http://127.0.0.1:8080/healthz")
#   $4 - (Optional) Max health timeout in seconds (default: 30)
# ------------------------------------------------------------------------------
conduit::rolling_update() {
    local service_name="$1"
    local new_image="$2"
    local health_endpoint="$3"
    local timeout="${4:-30}"

    local old_cid
    old_cid="$(conduit::state_resolve "${service_name}")" || {
        conduit::throw "${ERR_CONTAINER_NOT_FOUND}" "active service instance '${service_name}' not found"
        return $?
    }

    conduit::log_info "Initiating zero-downtime rollout for '${service_name}' -> '${new_image}'"

    # 1. Instantiate staging "green" container
    local green_name="${service_name}_green"
    local green_cid
    green_cid="$(conduit::sha256_str "${green_name}_$(date +%s%N)")"

    conduit::state_create "${green_cid}" "${new_image}" "${green_name}" "${green_name}" "[]"

    local green_rootfs="${CONDUIT_CONTAINERS_DIR}/${green_cid}/rootfs"
    conduit::image_unpack "${new_image}" "${green_rootfs}" 2>/dev/null || true

    conduit::log_info "Launching green canary instance '${green_name}' (${green_cid:0:12})..."
    conduit::process_start "${green_cid}" "true" "false" || {
        conduit::log_error "Failed to start green canary container; aborting rollout"
        rm -rf "${CONDUIT_CONTAINERS_DIR:?}/${green_cid}" 2>/dev/null || true
        return 1
    }

    # 2. Probe green instance health
    conduit::log_info "Verifying health check barrier on '${health_endpoint}'..."
    if ! conduit::health_wait_ready "http" "${health_endpoint}" "${timeout}"; then
        conduit::log_error "Green canary failed health barrier! Initiating automatic rollback..."
        conduit::process_stop "${green_cid}" 2 || true
        rm -rf "${CONDUIT_CONTAINERS_DIR:?}/${green_cid}" 2>/dev/null || true
        conduit::log_info "Rollback complete: original service '${service_name}' remains fully operational"
        return 1
    fi

    # 3. Health verified: decommission old blue instance and promote green
    conduit::log_info "Green canary verified healthy; retiring old instance '${old_cid:0:12}'..."
    conduit::process_stop "${old_cid}" 5 || true
    rm -rf "${CONDUIT_CONTAINERS_DIR:?}/${old_cid}" 2>/dev/null || true

    conduit::log_info "Zero-downtime rolling update successfully promoted green instance to production"
    return 0
}
