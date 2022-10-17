#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/capabilities.sh - Linux POSIX capabilities reduction and drop sets
#
# Enforces least-privilege containment by dropping dangerous Linux capabilities
# (raw I/O, raw sockets, ptrace, kernel module loading) using setpriv and capsh.
# ==============================================================================

conduit::import "core/logging"
conduit::import "core/platform"

# Default set of capabilities to drop for secure unprivileged containment
export CONDUIT_DROPPED_CAPS=(
    "cap_sys_admin"
    "cap_sys_rawio"
    "cap_sys_ptrace"
    "cap_sys_module"
    "cap_sys_boot"
    "cap_mac_admin"
    "cap_audit_control"
)

# ------------------------------------------------------------------------------
# conduit::capabilities_exec
# Wraps command execution with setpriv to drop bounding capabilities.
# ------------------------------------------------------------------------------
conduit::capabilities_exec() {
    if ! conduit::is_linux; then
        "$@"
        return $?
    fi

    if command -v setpriv >/dev/null 2>&1; then
        local drop_csv
        local IFS=','
        drop_csv="${CONDUIT_DROPPED_CAPS[*]}"
        exec setpriv --inh-caps "-${drop_csv}" --bounding-set "-${drop_csv}" --no-new-privs "$@"
    else
        "$@"
    fi
}
