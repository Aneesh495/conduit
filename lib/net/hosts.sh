#!/usr/bin/env bash
# ==============================================================================
# lib/net/hosts.sh - Container service discovery and /etc/hosts synthesis
#
# Generates deterministic hostname resolution maps across multi-container
# networks, enabling service-name discovery without external DNS daemons.
# ==============================================================================

conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::hosts_add_entry
# Adds an IP to hostname mapping in the target rootfs /etc/hosts file.
# Arguments:
#   $1 - Path to container rootfs
#   $2 - IP address
#   $3 - Hostname / service name
#   $@ - Additional aliases
# ------------------------------------------------------------------------------
conduit::hosts_add_entry() {
    local rootfs="$1"
    local ip_addr="$2"
    local hostname="$3"
    shift 3

    local hosts_file="${rootfs}/etc/hosts"
    mkdir -p "$(dirname "${hosts_file}")"

    # Remove existing entry for hostname if present
    if [[ -f "${hosts_file}" ]]; then
        local tmp="${hosts_file}.tmp.$$"
        grep -v "[[:space:]]${hostname}\([[:space:]]\|$\)" "${hosts_file}" > "${tmp}" 2>/dev/null || true
        mv -f "${tmp}" "${hosts_file}"
    fi

    # Append new entry with aliases
    echo "${ip_addr} ${hostname} $*" >> "${hosts_file}"
    conduit::log_trace "Appended /etc/hosts mapping: ${ip_addr} -> ${hostname} $*"
    return 0
}
