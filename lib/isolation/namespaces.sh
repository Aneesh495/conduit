#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/namespaces.sh - Linux kernel namespace isolation synthesis
#
# Configures mount, PID, network, IPC, and UTS namespace boundaries using
# unshare and user-namespace UID mapping for unprivileged containerization.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"
conduit::import "core/platform"

# ------------------------------------------------------------------------------
# conduit::namespace_exec
# Spawns a command within isolated Linux kernel namespaces.
# Arguments:
#   $1 - Container rootfs path
#   $2 - Container hostname
#   $3 - Network namespace mode ('none', 'bridge', 'host')
#   $@ - Command and arguments to execute
# ------------------------------------------------------------------------------
conduit::namespace_exec() {
    local rootfs="$1"
    local hostname="$2"
    local net_mode="$3"
    shift 3

    if ! conduit::is_linux; then
        return 1
    fi

    local -a unshare_args=(
        "--mount"
        "--uts"
        "--ipc"
        "--pid"
        "--fork"
    )

    # If unprivileged user, map root user via user namespaces
    if [[ "${CONDUIT_IS_ROOT}" != "true" ]]; then
        unshare_args+=("--user" "--map-root-user")
    fi

    # Network namespace isolation
    if [[ "${net_mode}" == "none" ]]; then
        unshare_args+=("--net")
    fi

    # Execute isolated process using unshare
    exec unshare "${unshare_args[@]}" \
        chroot "${rootfs}" "$@"
}
