#!/usr/bin/env bash
# ==============================================================================
# lib/net/ipam.sh - Deterministic IP Address Management (IPAM) and CIDR allocator
#
# Allocates deterministic IPv4 subnets, tracks active leases in state files,
# detects collisions, and releases leased addresses upon container shutdown.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"

export CONDUIT_DEFAULT_SUBNET="10.88.0.0/16"
export CONDUIT_DEFAULT_GATEWAY="10.88.0.1"

# ------------------------------------------------------------------------------
# conduit::ipam_init
# Initializes the IPAM database for the given network name.
# ------------------------------------------------------------------------------
conduit::ipam_init() {
    local net_name="${1:-conduit}"
    local net_dir="${CONDUIT_NETWORKS_DIR}/${net_name}"
    mkdir -p "${net_dir}"

    local leases_file="${net_dir}/leases.txt"
    if [[ ! -f "${leases_file}" ]]; then
        touch "${leases_file}"
    fi

    local config_file="${net_dir}/config.json"
    if [[ ! -f "${config_file}" ]]; then
        cat <<EOF > "${config_file}"
{
  "name": "${net_name}",
  "subnet": "${CONDUIT_DEFAULT_SUBNET}",
  "gateway": "${CONDUIT_DEFAULT_GATEWAY}",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi
}

# ------------------------------------------------------------------------------
# conduit::ipam_allocate
# Allocates next available IP in subnet or verifies requested static IP.
# Arguments:
#   $1 - Network name (default: "conduit")
#   $2 - Container ID
#   $3 - (Optional) Requested static IPv4 address
# Output:
#   Allocated IPv4 address on stdout
# ------------------------------------------------------------------------------
conduit::ipam_allocate() {
    local net_name="${1:-conduit}"
    local container_id="$2"
    local requested_ip="${3:-}"

    conduit::ipam_init "${net_name}"
    local leases_file="${CONDUIT_NETWORKS_DIR}/${net_name}/leases.txt"

    # If static IP requested, check if already leased
    if [[ -n "${requested_ip}" ]]; then
        if grep -q "^${requested_ip} " "${leases_file}" 2>/dev/null; then
            conduit::throw "${ERR_NETWORK_COLLISION}" "IP address '${requested_ip}' is already allocated"
            return $?
        fi
        echo "${requested_ip} ${container_id} $(date +%s)" >> "${leases_file}"
        echo "${requested_ip}"
        return 0
    fi

    # Sequential search in 10.88.0.2 .. 10.88.255.254
    # Subnet prefix 10.88.0.
    local i
    for (( i = 2; i < 254; i++ )); do
        local candidate="10.88.0.${i}"
        if ! grep -q "^${candidate} " "${leases_file}" 2>/dev/null; then
            echo "${candidate} ${container_id} $(date +%s)" >> "${leases_file}"
            conduit::log_debug "IPAM leased ${candidate} to container '${container_id:0:12}'"
            echo "${candidate}"
            return 0
        fi
    done

    conduit::throw "${ERR_IPAM_EXHAUSTED}" "IPAM subnet address space exhausted for network '${net_name}'"
    return $?
}

# ------------------------------------------------------------------------------
# conduit::ipam_release
# Releases any leased IP assigned to the designated container ID.
# ------------------------------------------------------------------------------
conduit::ipam_release() {
    local net_name="${1:-conduit}"
    local container_id="$2"

    local leases_file="${CONDUIT_NETWORKS_DIR}/${net_name}/leases.txt"
    [[ ! -f "${leases_file}" ]] && return 0

    local tmp="${leases_file}.tmp.$$"
    grep -v " ${container_id} " "${leases_file}" > "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${leases_file}"
    conduit::log_debug "IPAM released lease for container '${container_id:0:12}'"
    return 0
}
