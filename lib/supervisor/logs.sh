#!/usr/bin/env bash
# ==============================================================================
# lib/supervisor/logs.sh - Container log multiplexing, tailing, and rotation
#
# Manages append-only container output journals, ISO-8601 timestamp injection,
# live streaming follow pipes (tail -f), and size-bounded ring buffer rotation.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "supervisor/state"

# ------------------------------------------------------------------------------
# conduit::logs_combined_file
# Returns path to container combined.log file.
# ------------------------------------------------------------------------------
conduit::logs_combined_file() {
    local container_id="$1"
    echo "${CONDUIT_CONTAINERS_DIR}/${container_id}/combined.log"
}

# ------------------------------------------------------------------------------
# conduit::logs_cat
# Prints existing log contents for a container.
# Arguments:
#   $1 - Container ID or name
#   $2 - (Optional) Tail line count (default: all)
#   $3 - (Optional) Show timestamps boolean (default: false)
# ------------------------------------------------------------------------------
conduit::logs_cat() {
    local query="$1"
    local tail_count="${2:-}"
    local show_timestamps="${3:-false}"

    local container_id
    container_id="$(conduit::state_resolve "${query}")" || return 1

    local log_file
    log_file="$(conduit::logs_combined_file "${container_id}")"

    if [[ ! -f "${log_file}" ]]; then
        return 0
    fi

    if [[ -n "${tail_count}" ]] && conduit::is_uint "${tail_count}"; then
        tail -n "${tail_count}" "${log_file}"
    else
        cat "${log_file}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::logs_follow
# Streams logs in real time as they are emitted by the container workload.
# ------------------------------------------------------------------------------
conduit::logs_follow() {
    local query="$1"
    local tail_count="${2:-10}"

    local container_id
    container_id="$(conduit::state_resolve "${query}")" || return 1

    local log_file
    log_file="$(conduit::logs_combined_file "${container_id}")"
    touch "${log_file}"

    tail -n "${tail_count}" -f "${log_file}"
}
