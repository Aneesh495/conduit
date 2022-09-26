#!/usr/bin/env bash
# ==============================================================================
# lib/storage/volume.sh - Persistent named volume and bind mount management
#
# Provides isolated data persistence volumes, host directory bind mounts,
# permission inheritance, and container volume mounting orchestration.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::volume_init
# Ensures the volume storage directory hierarchy exists.
# ------------------------------------------------------------------------------
conduit::volume_init() {
    mkdir -p "${CONDUIT_VOLUMES_DIR}"
}

# ------------------------------------------------------------------------------
# conduit::volume_create
# Creates a named persistent volume.
# Arguments:
#   $1 - Volume identifier (alphanumeric name)
# ------------------------------------------------------------------------------
conduit::volume_create() {
    local name="$1"
    if ! conduit::is_alphanumeric "${name}"; then
        conduit::throw "${ERR_INVALID_ARG}" "invalid volume name '${name}'; must be alphanumeric"
        return $?
    fi

    conduit::volume_init

    local vol_dir="${CONDUIT_VOLUMES_DIR}/${name}"
    local data_dir="${vol_dir}/_data"

    if [[ -d "${vol_dir}" ]]; then
        conduit::log_debug "Volume '${name}' already exists"
        return 0
    fi

    mkdir -p "${data_dir}"
    local meta_file="${vol_dir}/metadata.json"
    cat <<EOF > "${meta_file}"
{
  "name": "${name}",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "mountpoint": "${data_dir}"
}
EOF

    conduit::log_info "Created volume '${name}' at '${data_dir}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::volume_data_path
# Returns the absolute path to the volume's underlying data storage.
# ------------------------------------------------------------------------------
conduit::volume_data_path() {
    local name="$1"
    echo "${CONDUIT_VOLUMES_DIR}/${name}/_data"
}

# ------------------------------------------------------------------------------
# conduit::volume_remove
# Deletes a persistent named volume.
# ------------------------------------------------------------------------------
conduit::volume_remove() {
    local name="$1"
    local vol_dir="${CONDUIT_VOLUMES_DIR}/${name}"

    if [[ ! -d "${vol_dir}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "volume '${name}' does not exist"
        return $?
    fi

    rm -rf "${vol_dir}"
    conduit::log_info "Removed volume '${name}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::parse_mount_spec
# Parses "-v host_or_vol:container_dir[:opts]" string.
# Output: SOURCE TARGET READONLY_BOOL
# ------------------------------------------------------------------------------
conduit::parse_mount_spec() {
    local spec="$1"
    local ro="false"

    local colons="${spec//[^:]/}"
    local count="${#colons}"

    local src dst opts=""
    if (( count == 1 )); then
        src="${spec%%:*}"
        dst="${spec##*:}"
    elif (( count == 2 )); then
        src="${spec%%:*}"
        local rest="${spec#*:}"
        dst="${rest%%:*}"
        opts="${rest##*:}"
        [[ "${opts}" == *"ro"* ]] && ro="true"
    else
        conduit::throw "${ERR_INVALID_ARG}" "invalid volume specification '${spec}'"
        return $?
    fi

    # Check if src is an absolute host path or a named volume
    if [[ "${src}" == /* ]]; then
        # Host bind mount
        echo "${src} ${dst} ${ro}"
    else
        # Named volume: ensure it exists
        conduit::volume_create "${src}" || return 1
        local vol_path
        vol_path="$(conduit::volume_data_path "${src}")"
        echo "${vol_path} ${dst} ${ro}"
    fi

    return 0
}
