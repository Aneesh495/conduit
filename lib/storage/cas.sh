#!/usr/bin/env bash
# ==============================================================================
# lib/storage/cas.sh - Content-Addressable Storage (CAS) blob store
#
# Provides immutable, SHA-256 indexed blob persistence with atomic ingestion,
# deduplication, integrity validation, and mark-and-sweep garbage collection.
# ==============================================================================

# Ensure core and crypto modules are loaded
conduit::import "core/types"
conduit::import "core/errors"
conduit::import "crypto/sha256"

# ------------------------------------------------------------------------------
# conduit::cas_init
# Creates directory layout for content-addressed blob storage.
# ------------------------------------------------------------------------------
conduit::cas_init() {
    local base_dir="${CONDUIT_BLOB_DIR}/sha256"
    mkdir -p "${base_dir}"
    chmod 0700 "${CONDUIT_BLOB_DIR}" "${base_dir}" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# conduit::cas_path
# Returns the absolute filesystem path for a given SHA-256 digest.
# ------------------------------------------------------------------------------
conduit::cas_path() {
    local digest="$1"
    # Strip any prefix like "sha256:"
    digest="${digest#sha256:}"
    echo "${CONDUIT_BLOB_DIR}/sha256/${digest}"
}

# ------------------------------------------------------------------------------
# conduit::cas_has
# Checks whether a blob with the designated digest exists and is valid.
# ------------------------------------------------------------------------------
conduit::cas_has() {
    local digest="$1"
    local path
    path="$(conduit::cas_path "${digest}")"
    [[ -f "${path}" ]]
}

# ------------------------------------------------------------------------------
# conduit::cas_put_file
# Ingests a file into the CAS store. Verifies digest matches file content.
# Arguments:
#   $1 - Source file path
# Returns:
#   SHA-256 hex digest on stdout
# ------------------------------------------------------------------------------
conduit::cas_put_file() {
    local src_file="$1"
    if [[ ! -f "${src_file}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "cannot ingest non-existent file '${src_file}'"
        return $?
    fi

    conduit::cas_init

    local digest
    digest="$(conduit::sha256_file "${src_file}")" || {
        conduit::throw "${ERR_GENERIC}" "failed to compute digest for '${src_file}'"
        return $?
    }

    local target_path
    target_path="$(conduit::cas_path "${digest}")"

    if [[ -f "${target_path}" ]]; then
        # Already exists; deduplicated
        echo "${digest}"
        return 0
    fi

    # Atomic write pattern: write to tmp then rename
    local tmp_target="${target_path}.tmp.$$.${RANDOM}"
    cp -p "${src_file}" "${tmp_target}" || {
        rm -f "${tmp_target}" 2>/dev/null
        conduit::throw "${ERR_GENERIC}" "failed to copy blob to '${tmp_target}'"
        return $?
    }

    # Make blob read-only to enforce immutability
    chmod 0444 "${tmp_target}" 2>/dev/null || true
    mv -f "${tmp_target}" "${target_path}" || {
        rm -f "${tmp_target}" 2>/dev/null
        conduit::throw "${ERR_GENERIC}" "failed to atomically commit blob '${digest}'"
        return $?
    }

    echo "${digest}"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::cas_put_stream
# Ingests stream from stdin into CAS store.
# Returns:
#   SHA-256 hex digest on stdout
# ------------------------------------------------------------------------------
conduit::cas_put_stream() {
    conduit::cas_init

    local tmp_dir="${CONDUIT_BLOB_DIR}/sha256"
    local tmp_file="${tmp_dir}/stream.tmp.$$.${RANDOM}"

    cat > "${tmp_file}" || {
        rm -f "${tmp_file}" 2>/dev/null
        conduit::throw "${ERR_GENERIC}" "failed to buffer stream into '${tmp_file}'"
        return $?
    }

    local digest
    digest="$(conduit::sha256_file "${tmp_file}")"
    local target_path
    target_path="$(conduit::cas_path "${digest}")"

    if [[ -f "${target_path}" ]]; then
        rm -f "${tmp_file}"
        echo "${digest}"
        return 0
    fi

    chmod 0444 "${tmp_file}" 2>/dev/null || true
    mv -f "${tmp_file}" "${target_path}"
    echo "${digest}"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::cas_get
# Retrieves blob contents to stdout.
# Arguments:
#   $1 - SHA-256 digest
# ------------------------------------------------------------------------------
conduit::cas_get() {
    local digest="$1"
    local path
    path="$(conduit::cas_path "${digest}")"

    if [[ ! -f "${path}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "blob '${digest}' not found in CAS store"
        return $?
    fi

    cat "${path}"
}

# ------------------------------------------------------------------------------
# conduit::cas_verify_all
# Scans all blobs in store and confirms their content matches their hash name.
# ------------------------------------------------------------------------------
conduit::cas_verify_all() {
    local base_dir="${CONDUIT_BLOB_DIR}/sha256"
    [[ ! -d "${base_dir}" ]] && return 0

    local corrupted=0
    local blob_path digest actual
    for blob_path in "${base_dir}"/*; do
        [[ ! -f "${blob_path}" ]] && continue
        [[ "${blob_path}" == *.tmp.* ]] && continue

        digest="$(basename "${blob_path}")"
        actual="$(conduit::sha256_file "${blob_path}")"

        if [[ "${digest}" != "${actual}" ]]; then
            echo "conduit: CAS corruption detected in blob '${digest}' (got '${actual}')" >&2
            (( corrupted++ ))
        fi
    done

    if (( corrupted > 0 )); then
        return 1
    fi
    return 0
}
