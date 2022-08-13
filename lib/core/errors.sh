#!/usr/bin/env bash
# ==============================================================================
# lib/core/errors.sh - Structured exception handling and call-stack introspection
#
# Implements disciplined error reporting with call-stack frame introspection,
# distinct numerical exit status taxonomy, and try/catch/throw execution contexts.
# ==============================================================================

# Standard Conduit Exit Status taxonomy
export ERR_OK=0
export ERR_GENERIC=1
export ERR_INVALID_ARG=2
export ERR_FILE_NOT_FOUND=3
export ERR_PERMISSION_DENIED=4
export ERR_TIMEOUT=5
export ERR_NOT_IMPLEMENTED=6

export ERR_CONTAINER_NOT_FOUND=10
export ERR_CONTAINER_ALREADY_EXISTS=11
export ERR_CONTAINER_NOT_RUNNING=12
export ERR_CONTAINER_ALREADY_RUNNING=13
export ERR_CONTAINER_DEAD=14

export ERR_IMAGE_NOT_FOUND=20
export ERR_LAYER_CORRUPTED=21
export ERR_MANIFEST_INVALID=22

export ERR_COW_FAILURE=30
export ERR_SNAPSHOT_FAILED=31

export ERR_ISOLATION_FAILED=40
export ERR_CGROUP_FAILED=41
export ERR_SANDBOX_DENIED=42

export ERR_NETWORK_COLLISION=50
export ERR_PORT_IN_USE=51
export ERR_IPAM_EXHAUSTED=52

export ERR_HEALTH_CHECK_FAILED=60
export ERR_DAG_CYCLE=70

# Thread-local exception storage
declare -g _CONDUIT_LAST_ERROR_CODE=0
declare -g _CONDUIT_LAST_ERROR_MSG=""
declare -g _CONDUIT_LAST_ERROR_FILE=""
declare -g _CONDUIT_LAST_ERROR_LINE=0

# ------------------------------------------------------------------------------
# conduit::stack_trace
# Prints a formatted call stack to stderr showing callers, files, and lines.
# ------------------------------------------------------------------------------
conduit::stack_trace() {
    local start_frame="${1:-1}"
    local frame_count="${#FUNCNAME[@]}"

    echo "conduit: stack trace (most recent call first):" >&2
    local i
    for (( i = start_frame; i < frame_count; i++ )); do
        local func="${FUNCNAME[i]}"
        local src="${BASH_SOURCE[i]:-unknown}"
        local line="${BASH_LINENO[i-1]:-0}"
        printf "  at %s (%s:%s)\n" "${func}" "${src}" "${line}" >&2
    done
}

# ------------------------------------------------------------------------------
# conduit::throw
# Emits an error message, records the exception, optionally prints a stack trace,
# and returns the designated status code.
# Arguments:
#   $1 - Error code (default: 1)
#   $2 - Error message
# ------------------------------------------------------------------------------
conduit::throw() {
    local code="${1:-1}"
    local msg="${2:-unspecified error}"
    local caller_file="${BASH_SOURCE[1]:-unknown}"
    local caller_line="${BASH_LINENO[0]:-0}"

    _CONDUIT_LAST_ERROR_CODE="${code}"
    _CONDUIT_LAST_ERROR_MSG="${msg}"
    _CONDUIT_LAST_ERROR_FILE="${caller_file}"
    _CONDUIT_LAST_ERROR_LINE="${caller_line}"

    if [[ "${CONDUIT_TRACE_ERRORS:-0}" == "1" ]]; then
        echo "conduit: exception [code ${code}]: ${msg}" >&2
        conduit::stack_trace 2
    fi

    return "${code}"
}

# ------------------------------------------------------------------------------
# Try / Catch execution wrapper
# Usage:
#   conduit::try my_risky_function arg1 arg2
#   if conduit::catch; then
#       echo "Caught error: ${_CONDUIT_LAST_ERROR_MSG}"
#   fi
# ------------------------------------------------------------------------------
conduit::try() {
    _CONDUIT_LAST_ERROR_CODE=0
    _CONDUIT_LAST_ERROR_MSG=""
    "$@"
    local status=$?
    if (( status != 0 )); then
        _CONDUIT_LAST_ERROR_CODE="${status}"
        return "${status}"
    fi
    return 0
}

conduit::catch() {
    if (( _CONDUIT_LAST_ERROR_CODE != 0 )); then
        return 0 # Error was caught
    fi
    return 1 # No error
}

conduit::get_last_error() {
    echo "${_CONDUIT_LAST_ERROR_CODE}:${_CONDUIT_LAST_ERROR_MSG}"
}

# ------------------------------------------------------------------------------
# conduit::error_name
# Converts numeric error code to canonical name string.
# ------------------------------------------------------------------------------
conduit::error_name() {
    local code="$1"
    case "${code}" in
        0) echo "ERR_OK" ;;
        1) echo "ERR_GENERIC" ;;
        2) echo "ERR_INVALID_ARG" ;;
        3) echo "ERR_FILE_NOT_FOUND" ;;
        4) echo "ERR_PERMISSION_DENIED" ;;
        5) echo "ERR_TIMEOUT" ;;
        6) echo "ERR_NOT_IMPLEMENTED" ;;
        10) echo "ERR_CONTAINER_NOT_FOUND" ;;
        11) echo "ERR_CONTAINER_ALREADY_EXISTS" ;;
        12) echo "ERR_CONTAINER_NOT_RUNNING" ;;
        13) echo "ERR_CONTAINER_ALREADY_RUNNING" ;;
        14) echo "ERR_CONTAINER_DEAD" ;;
        20) echo "ERR_IMAGE_NOT_FOUND" ;;
        21) echo "ERR_LAYER_CORRUPTED" ;;
        22) echo "ERR_MANIFEST_INVALID" ;;
        30) echo "ERR_COW_FAILURE" ;;
        31) echo "ERR_SNAPSHOT_FAILED" ;;
        40) echo "ERR_ISOLATION_FAILED" ;;
        41) echo "ERR_CGROUP_FAILED" ;;
        42) echo "ERR_SANDBOX_DENIED" ;;
        50) echo "ERR_NETWORK_COLLISION" ;;
        51) echo "ERR_PORT_IN_USE" ;;
        52) echo "ERR_IPAM_EXHAUSTED" ;;
        60) echo "ERR_HEALTH_CHECK_FAILED" ;;
        70) echo "ERR_DAG_CYCLE" ;;
        *) echo "ERR_UNKNOWN_${code}" ;;
    esac
}
