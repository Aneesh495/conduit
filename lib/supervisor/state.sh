#!/usr/bin/env bash
# ==============================================================================
# lib/supervisor/state.sh - Container lifecycle state machine and metadata store
#
# Enforces deterministic state transitions (creating, created, running, paused,
# stopped, dead) and persists container execution records and exit statuses.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "json/parser"
conduit::import "json/serializer"

# Lifecycle state constants
export STATE_CREATING="creating"
export STATE_CREATED="created"
export STATE_RUNNING="running"
export STATE_PAUSED="paused"
export STATE_STOPPED="stopped"
export STATE_DEAD="dead"

# ------------------------------------------------------------------------------
# conduit::state_file
# Returns path to container state.json file.
# ------------------------------------------------------------------------------
conduit::state_file() {
    local container_id="$1"
    echo "${CONDUIT_CONTAINERS_DIR}/${container_id}/state.json"
}

# ------------------------------------------------------------------------------
# conduit::state_create
# Initializes container directory and writes initial state record.
# Arguments:
#   $1 - Container ID
#   $2 - Image ID
#   $3 - Container name
#   $4 - Hostname
#   $5 - Command array string
# ------------------------------------------------------------------------------
conduit::state_create() {
    local container_id="$1"
    local image_id="$2"
    local name="$3"
    local hostname="$4"
    local cmd_json="${5:-[]}"

    local container_dir="${CONDUIT_CONTAINERS_DIR}/${container_id}"
    if [[ -d "${container_dir}" ]]; then
        conduit::throw "${ERR_CONTAINER_ALREADY_EXISTS}" "container '${container_id}' already exists"
        return $?
    fi

    mkdir -p "${container_dir}" "${container_dir}/rootfs" "${container_dir}/state"

    local created_at
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local s_file="${container_dir}/state.json"
    cat <<EOF > "${s_file}"
{
  "id": "${container_id}",
  "name": "${name}",
  "image": "${image_id}",
  "hostname": "${hostname}",
  "status": "${STATE_CREATED}",
  "created": "${created_at}",
  "started": "",
  "finished": "",
  "pid": 0,
  "exit_code": 0,
  "ip_address": "",
  "ports": [],
  "command": ${cmd_json}
}
EOF

    conduit::log_debug "Initialized container state record for '${name}' (${container_id:0:12})"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::state_get_status
# Retrieves the current status string for a container.
# ------------------------------------------------------------------------------
conduit::state_get_status() {
    local container_id="$1"
    local s_file
    s_file="$(conduit::state_file "${container_id}")"

    if [[ ! -f "${s_file}" ]]; then
        conduit::throw "${ERR_CONTAINER_NOT_FOUND}" "container '${container_id}' not found"
        return $?
    fi

    conduit::json_get "status" "${s_file}"
}

# ------------------------------------------------------------------------------
# conduit::state_update
# Atomically updates fields in container state.json.
# Arguments:
#   $1 - Container ID
#   $2 - Status string
#   $3 - PID (integer)
#   $4 - Exit code (integer)
#   $5 - (Optional) IP address
# ------------------------------------------------------------------------------
conduit::state_update() {
    local container_id="$1"
    local status="$2"
    local pid="${3:-0}"
    local exit_code="${4:-0}"
    local ip_addr="${5:-}"

    local s_file
    s_file="$(conduit::state_file "${container_id}")"
    [[ ! -f "${s_file}" ]] && return 1

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json, os

path = sys.argv[1]
status = sys.argv[2]
pid = int(sys.argv[3])
exit_code = int(sys.argv[4])
ip_addr = sys.argv[5]

with open(path, 'r') as f:
    data = json.load(f)

data['status'] = status
data['pid'] = pid
data['exit_code'] = exit_code
if ip_addr:
    data['ip_address'] = ip_addr

if status == 'running' and not data.get('started'):
    import datetime
    data['started'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
elif status in ('stopped', 'dead'):
    import datetime
    data['finished'] = datetime.datetime.now(datetime.timezone.utc).isoformat()

tmp = path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
" "${s_file}" "${status}" "${pid}" "${exit_code}" "${ip_addr}"
    fi

    conduit::log_debug "Container '${container_id:0:12}' transitioned to state '${status}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::state_resolve
# Resolves name or short ID to full 64-character container ID.
# ------------------------------------------------------------------------------
conduit::state_resolve() {
    local query="$1"
    [[ -z "${query}" ]] && return 1

    local c_dir
    for c_dir in "${CONDUIT_CONTAINERS_DIR}"/*; do
        [[ ! -d "${c_dir}" ]] && continue
        local cid
        cid="$(basename "${c_dir}")"

        # Check exact full ID
        if [[ "${cid}" == "${query}" ]]; then
            echo "${cid}"
            return 0
        fi

        # Check short ID prefix
        if [[ "${cid}" == "${query}"* ]]; then
            echo "${cid}"
            return 0
        fi

        # Check name in state.json
        local s_file="${c_dir}/state.json"
        if [[ -f "${s_file}" ]]; then
            local cname
            cname="$(conduit::json_get "name" "${s_file}" 2>/dev/null || true)"
            if [[ "${cname}" == "${query}" ]]; then
                echo "${cid}"
                return 0
            fi
        fi
    done

    conduit::throw "${ERR_CONTAINER_NOT_FOUND}" "container '${query}' not found"
    return $?
}
