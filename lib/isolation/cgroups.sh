#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/cgroups.sh - Linux cgroups v2 resource controller
#
# Enforces kernel-level resource quotas (CPU bandwidth, memory RSS limits,
# forkbomb PID limits) using the unified cgroups v2 hierarchy.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"
conduit::import "core/platform"

export CGROUP_ROOT="/sys/fs/cgroup/conduit"

# ------------------------------------------------------------------------------
# conduit::cgroup_create
# Initializes a dedicated cgroup v2 slice for the container.
# Arguments:
#   $1 - Container ID
#   $2 - (Optional) Memory limit in bytes (0 for unlimited)
#   $3 - (Optional) CPU quota percentage (0 for 100%)
#   $4 - (Optional) Max PIDs limit (0 for unlimited)
# ------------------------------------------------------------------------------
conduit::cgroup_create() {
    local container_id="$1"
    local mem_bytes="${2:-0}"
    local cpu_percent="${3:-0}"
    local max_pids="${4:-0}"

    if ! conduit::is_linux || [[ "${CONDUIT_HAS_CGROUPS_V2}" != "true" ]]; then
        return 0
    fi

    local cg_dir="${CGROUP_ROOT}/${container_id}"
    mkdir -p "${cg_dir}" 2>/dev/null || {
        conduit::log_warn "Unable to create cgroup directory '${cg_dir}' (requires cgroup v2 delegation or root)"
        return 0
    }

    # Apply Memory limit: memory.max
    if (( mem_bytes > 0 )) && [[ -f "${cg_dir}/memory.max" ]]; then
        echo "${mem_bytes}" > "${cg_dir}/memory.max" 2>/dev/null || true
        conduit::log_debug "Configured cgroup memory.max=${mem_bytes}"
    fi

    # Apply CPU limit: cpu.max quota period (period default: 100000 us = 100ms)
    if (( cpu_percent > 0 )) && [[ -f "${cg_dir}/cpu.max" ]]; then
        local period=100000
        local quota=$(( period * cpu_percent / 100 ))
        echo "${quota} ${period}" > "${cg_dir}/cpu.max" 2>/dev/null || true
        conduit::log_debug "Configured cgroup cpu.max=${quota} ${period}"
    fi

    # Apply PIDs limit: pids.max
    if (( max_pids > 0 )) && [[ -f "${cg_dir}/pids.max" ]]; then
        echo "${max_pids}" > "${cg_dir}/pids.max" 2>/dev/null || true
        conduit::log_debug "Configured cgroup pids.max=${max_pids}"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# conduit::cgroup_attach
# Enrolls a process PID into the container's cgroup slice.
# ------------------------------------------------------------------------------
conduit::cgroup_attach() {
    local container_id="$1"
    local pid="$2"

    if ! conduit::is_linux || [[ "${CONDUIT_HAS_CGROUPS_V2}" != "true" ]]; then
        return 0
    fi

    local cg_dir="${CGROUP_ROOT}/${container_id}"
    if [[ -f "${cg_dir}/cgroup.procs" ]]; then
        echo "${pid}" > "${cg_dir}/cgroup.procs" 2>/dev/null || true
        conduit::log_debug "Attached PID ${pid} to cgroup '${container_id}'"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# conduit::cgroup_destroy
# Removes container cgroup slice upon termination.
# ------------------------------------------------------------------------------
conduit::cgroup_destroy() {
    local container_id="$1"

    if ! conduit::is_linux || [[ "${CONDUIT_HAS_CGROUPS_V2}" != "true" ]]; then
        return 0
    fi

    local cg_dir="${CGROUP_ROOT}/${container_id}"
    if [[ -d "${cg_dir}" ]]; then
        rmdir "${cg_dir}" 2>/dev/null || true
    fi
    return 0
}
