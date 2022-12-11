#!/usr/bin/env bash
# ==============================================================================
# lib/supervisor/process.sh - Container process supervisor and sub-reaper
#
# Spawns isolated container workloads in foreground or background, reaps exit
# statuses, manages graceful SIGTERM/SIGKILL timeouts, and coordinates cleanup.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "storage/cow_tree"
conduit::import "isolation/sandbox"
conduit::import "supervisor/state"
conduit::import "supervisor/logs"
conduit::import "supervisor/pty"
conduit::import "net/ipam"
conduit::import "net/proxy"

# ------------------------------------------------------------------------------
# conduit::process_start
# Launches container workload in detached or foreground mode.
# Arguments:
#   $1 - Container ID
#   $2 - Detach boolean ('true' or 'false')
#   $3 - Interactive boolean ('true' or 'false')
# ------------------------------------------------------------------------------
conduit::process_start() {
    local container_id="$1"
    local detach="${2:-false}"
    local interactive="${3:-false}"

    local container_dir="${CONDUIT_CONTAINERS_DIR}/${container_id}"
    local s_file="${container_dir}/state.json"

    if [[ ! -f "${s_file}" ]]; then
        conduit::throw "${ERR_CONTAINER_NOT_FOUND}" "container '${container_id}' not found"
        return $?
    fi

    local current_status
    current_status="$(conduit::state_get_status "${container_id}")"
    if [[ "${current_status}" == "${STATE_RUNNING}" ]]; then
        conduit::throw "${ERR_CONTAINER_ALREADY_RUNNING}" "container '${container_id}' is already running"
        return $?
    fi

    local rootfs="${container_dir}/rootfs"
    local hostname
    hostname="$(conduit::json_get "hostname" "${s_file}")"
    local state_dir="${container_dir}/state"

    local log_file
    log_file="$(conduit::logs_combined_file "${container_id}")"
    touch "${log_file}"

    # Extract command array from state
    local -a cmd=("/bin/sh")
    local cmd_str
    cmd_str="$(conduit::json_get "command" "${s_file}" 2>/dev/null || true)"
    if [[ -n "${cmd_str}" && "${cmd_str}" != "[]" && "${cmd_str}" != "null" ]]; then
        # Parse command tokens
        read -r -a cmd <<< "$(echo "${cmd_str}" | tr -d '[]",')"
    fi

    # Allocate IP address
    local ip_addr
    ip_addr="$(conduit::ipam_allocate "conduit" "${container_id}")" || ip_addr="127.0.0.1"

    if [[ "${detach}" == "true" ]]; then
        # Launch detached background container workload
        (
            exec 1>>"${log_file}"
            exec 2>&1
            exec 0</dev/null
            conduit::sandbox_spawn "${container_id}" "${rootfs}" "${hostname}" "/" "bridge" "${state_dir}" "${cmd[@]}"
        ) </dev/null >>"${log_file}" 2>&1 &
        local child_pid=$!

        echo "${child_pid}" > "${container_dir}/pid"
        conduit::state_update "${container_id}" "${STATE_RUNNING}" "${child_pid}" 0 "${ip_addr}"
        conduit::log_info "Started container '${container_id:0:12}' in background (PID ${child_pid})"

        # Spawn asynchronous monitor loop to reap process when it exits
        (
            while kill -0 "${child_pid}" 2>/dev/null; do
                sleep 0.5
            done
            # Process terminated: update state
            conduit::state_update "${container_id}" "${STATE_STOPPED}" 0 0
            conduit::ipam_release "conduit" "${container_id}"
            conduit::log_debug "Container '${container_id:0:12}' process terminated; reaped state"
        ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null || true

        echo "${container_id}"
        return 0
    else
        # Foreground execution
        conduit::state_update "${container_id}" "${STATE_RUNNING}" "$$" 0 "${ip_addr}"
        if [[ "${interactive}" == "true" ]]; then
            conduit::pty_run conduit::sandbox_spawn "${container_id}" "${rootfs}" "${hostname}" "/" "bridge" "${state_dir}" "${cmd[@]}"
        else
            conduit::sandbox_spawn "${container_id}" "${rootfs}" "${hostname}" "/" "bridge" "${state_dir}" "${cmd[@]}"
        fi
        local exit_code=$?
        conduit::state_update "${container_id}" "${STATE_STOPPED}" 0 "${exit_code}"
        conduit::ipam_release "conduit" "${container_id}"
        return "${exit_code}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::process_stop
# Stops a running container using graceful SIGTERM followed by SIGKILL.
# Arguments:
#   $1 - Container ID or name
#   $2 - (Optional) Grace period timeout in seconds (default: 10)
# ------------------------------------------------------------------------------
conduit::process_stop() {
    local query="$1"
    local timeout="${2:-10}"

    local container_id
    container_id="$(conduit::state_resolve "${query}")" || return 1

    local container_dir="${CONDUIT_CONTAINERS_DIR}/${container_id}"
    local pid_file="${container_dir}/pid"

    if [[ ! -f "${pid_file}" ]]; then
        conduit::state_update "${container_id}" "${STATE_STOPPED}" 0 0
        return 0
    fi

    local target_pid
    target_pid="$(cat "${pid_file}" 2>/dev/null || true)"

    if [[ -n "${target_pid}" ]] && kill -0 "${target_pid}" 2>/dev/null; then
        conduit::log_info "Sending SIGTERM to container '${container_id:0:12}' (PID ${target_pid})..."
        kill -15 "${target_pid}" 2>/dev/null || true

        # Wait for graceful shutdown
        local waited=0
        while kill -0 "${target_pid}" 2>/dev/null; do
            sleep 0.5
            waited=$(( waited + 1 ))
            if (( waited >= timeout * 2 )); then
                conduit::log_warn "Grace period expired; sending SIGKILL to PID ${target_pid}..."
                kill -9 "${target_pid}" 2>/dev/null || true
                break
            fi
        done
    fi

    rm -f "${pid_file}"
    conduit::state_update "${container_id}" "${STATE_STOPPED}" 0 137
    conduit::ipam_release "conduit" "${container_id}"
    conduit::log_info "Stopped container '${container_id:0:12}'"
    return 0
}
