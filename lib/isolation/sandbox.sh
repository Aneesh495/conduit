#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/sandbox.sh - Unified execution driver and sandbox orchestrator
#
# Coordinates cross-platform isolation primitives, environment scrubbing,
# resource accounting, and process sandboxing across Linux and macOS Darwin.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "core/platform"
conduit::import "isolation/env"
conduit::import "isolation/rootfs"
conduit::import "isolation/darwin_sandbox"
conduit::import "isolation/cgroups"
conduit::import "isolation/namespaces"
conduit::import "isolation/capabilities"

# ------------------------------------------------------------------------------
# conduit::sandbox_spawn
# Prepares and executes an isolated process in the container environment.
# Arguments:
#   $1 - Container ID
#   $2 - Path to container rootfs
#   $3 - Hostname
#   $4 - Working directory inside container (e.g., "/")
#   $5 - Network mode ('bridge', 'none', 'host')
#   $6 - Path to container state directory
#   $@ - Command to run inside container
# ------------------------------------------------------------------------------
conduit::sandbox_spawn() {
    local container_id="$1"
    local rootfs="$2"
    local hostname="$3"
    local workdir="$4"
    local net_mode="$5"
    local state_dir="$6"
    shift 6

    local -a cmd=("$@")
    if (( ${#cmd[@]} == 0 )); then
        cmd=("/bin/sh")
    fi

    # 1. Prepare synthetic rootfs and device nodes
    conduit::rootfs_prepare "${rootfs}" "${hostname}" || return 1

    # 2. Build hermetic environment variables
    local -a env_pairs=()
    while IFS= read -r pair; do
        [[ -n "${pair}" ]] && env_pairs+=("${pair}")
    done < <(conduit::env_cleanse "${hostname}")

    # 3. Platform-specific execution dispatch
    if conduit::is_linux; then
        conduit::log_debug "Dispatching Linux container isolation for '${container_id}'"
        conduit::namespace_exec "${rootfs}" "${hostname}" "${net_mode}" "${cmd[@]}"
    elif conduit::is_darwin; then
        conduit::log_debug "Dispatching Darwin sandbox-exec isolation for '${container_id}'"
        local sb_profile="${state_dir}/sandbox.sb"
        conduit::darwin_compile_profile "${rootfs}" "${net_mode}" "${sb_profile}"

        # Execute inside container root directory with scrubbed environment
        (
            cd "${rootfs}" || exit 1
            export "${env_pairs[@]}"
            conduit::darwin_exec_sandboxed "${sb_profile}" "${cmd[@]}"
        )
    else
        # Fallback POSIX execution in rootfs directory
        (
            cd "${rootfs}" || exit 1
            export "${env_pairs[@]}"
            "${cmd[@]}"
        )
    fi
}
