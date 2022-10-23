#!/usr/bin/env bash
# ==============================================================================
# lib/net/port_alloc.sh - Host port reservation and conflict detection
#
# Detects host port availability using socket probing, assigns dynamic ephemeral
# ports, and validates network binding parameters.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::port_is_in_use
# Returns 0 if port is currently in use, 1 if free.
# ------------------------------------------------------------------------------
conduit::port_is_in_use() {
    local port="$1"

    # Test via /dev/tcp connection if supported in bash
    (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null && {
        exec 3>&-
        return 0 # Port is listening
    }

    # Test via lsof
    if command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    fi

    # Test via nc
    if command -v nc >/dev/null 2>&1; then
        nc -z 127.0.0.1 "${port}" 2>/dev/null && return 0
    fi

    return 1 # Port appears free
}

# ------------------------------------------------------------------------------
# conduit::port_allocate_ephemeral
# Finds and returns an available host TCP port in the ephemeral range (49152-65535).
# ------------------------------------------------------------------------------
conduit::port_allocate_ephemeral() {
    local candidate
    local i
    for (( i = 0; i < 50; i++ )); do
        candidate=$(( 49152 + (RANDOM % 16383) ))
        if ! conduit::port_is_in_use "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
    done

    conduit::throw "${ERR_PORT_IN_USE}" "failed to find free ephemeral host port"
    return $?
}
