#!/usr/bin/env bash
# ==============================================================================
# conduit.sh - Master bootstrap and runtime loader for the Conduit engine
#
# Conduit is a deterministic container runtime, copy-on-write storage engine,
# and process isolation fabric implemented in modular Bash.
# ==============================================================================

# Enforce bash 4.0 or newer for associative arrays and modern parameter expansion
if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "conduit: error: GNU Bash 4.0 or newer is required to execute Conduit." >&2
    echo "Current bash version: ${BASH_VERSION:-unknown}" >&2
    exit 1
fi

# Enable strict pipefail by default
set -o pipefail

# Determine the canonical root of the conduit installation
if [ -z "${CONDUIT_ROOT:-}" ]; then
    # Resolve symlinks if present to find canonical path
    _SOURCE="${BASH_SOURCE[0]}"
    while [ -h "${_SOURCE}" ]; do
        _DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
        _SOURCE="$(readlink "${_SOURCE}")"
        [[ ${_SOURCE} != /* ]] && _SOURCE="${_DIR}/${_SOURCE}"
    done
    CONDUIT_LIB="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
    CONDUIT_ROOT="$(cd -P "${CONDUIT_LIB}/.." && pwd)"
    export CONDUIT_ROOT
    export CONDUIT_LIB
fi

# Core version metadata
export CONDUIT_VERSION="0.9.0-alpha"
export CONDUIT_API_VERSION="1.0"

# Standard filesystem hierarchy paths for runtime state
export CONDUIT_STATE_DIR="${CONDUIT_STATE_DIR:-${HOME}/.conduit}"
export CONDUIT_IMAGES_DIR="${CONDUIT_STATE_DIR}/images"
export CONDUIT_CONTAINERS_DIR="${CONDUIT_STATE_DIR}/containers"
export CONDUIT_VOLUMES_DIR="${CONDUIT_STATE_DIR}/volumes"
export CONDUIT_NETWORKS_DIR="${CONDUIT_STATE_DIR}/networks"
export CONDUIT_BLOB_DIR="${CONDUIT_STATE_DIR}/blobs"
export CONDUIT_RUN_DIR="${CONDUIT_STATE_DIR}/run"
export CONDUIT_LOG_DIR="${CONDUIT_STATE_DIR}/logs"

# Global associative array tracking loaded modules to avoid circular imports
declare -g -A _CONDUIT_LOADED_MODULES

# ------------------------------------------------------------------------------
# conduit::import
# Dynamically loads a Conduit library module if not already loaded.
# Arguments:
#   $1 - Module path relative to lib/ (e.g., "core/types", "storage/cas")
# ------------------------------------------------------------------------------
conduit::import() {
    local module_rel="$1"
    # Normalize path suffix
    [[ "${module_rel}" != *.sh ]] && module_rel="${module_rel}.sh"

    local full_path="${CONDUIT_LIB}/${module_rel}"

    if [[ -n "${_CONDUIT_LOADED_MODULES[${module_rel}]:-}" ]]; then
        return 0
    fi

    if [[ ! -f "${full_path}" ]]; then
        echo "conduit: fatal: module '${module_rel}' not found at '${full_path}'" >&2
        return 1
    fi

    _CONDUIT_LOADED_MODULES["${module_rel}"]=1
    # shellcheck source=/dev/null
    source "${full_path}"
}

# ------------------------------------------------------------------------------
# conduit::init_environment
# Initializes the runtime state directories with restrictive permissions.
# ------------------------------------------------------------------------------
conduit::init_environment() {
    local d
    for d in \
        "${CONDUIT_STATE_DIR}" \
        "${CONDUIT_IMAGES_DIR}" \
        "${CONDUIT_CONTAINERS_DIR}" \
        "${CONDUIT_VOLUMES_DIR}" \
        "${CONDUIT_NETWORKS_DIR}" \
        "${CONDUIT_BLOB_DIR}" \
        "${CONDUIT_RUN_DIR}" \
        "${CONDUIT_LOG_DIR}"; do
        if [[ ! -d "${d}" ]]; then
            mkdir -p "${d}" || return 1
            chmod 0700 "${d}" 2>/dev/null || true
        fi
    done
    return 0
}
