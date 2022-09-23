#!/usr/bin/env bash
# ==============================================================================
# lib/storage/image.sh - Image repository, manifest v2 indexing, and layer unpacking
#
# Manages immutable image capsules, tag indices, multi-layer rootfs reconstruction,
# and deterministic metadata queries compliant with OCI image concepts.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "json/parser"
conduit::import "json/serializer"
conduit::import "storage/cas"
conduit::import "storage/layer"
conduit::import "storage/whiteout"

# ------------------------------------------------------------------------------
# conduit::image_init
# Initializes image repository state.
# ------------------------------------------------------------------------------
conduit::image_init() {
    mkdir -p "${CONDUIT_IMAGES_DIR}"
    local index_file="${CONDUIT_IMAGES_DIR}/index.json"
    if [[ ! -f "${index_file}" ]]; then
        echo "{}" > "${index_file}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::image_register
# Saves an image manifest and records it in the tag index.
# Arguments:
#   $1 - Canonical tag (e.g., "alpine:latest")
#   $2 - Manifest JSON string
# Returns:
#   Image ID (SHA-256 hash of manifest) on stdout
# ------------------------------------------------------------------------------
conduit::image_register() {
    local tag="$1"
    local manifest_json="$2"

    conduit::image_init

    # Compute image ID from manifest content
    local image_id
    image_id="$(conduit::sha256_str "${manifest_json}")" || return 1

    local manifest_file="${CONDUIT_IMAGES_DIR}/${image_id}.json"
    echo "${manifest_json}" > "${manifest_file}"

    # Update index mapping tag -> image_id
    local index_file="${CONDUIT_IMAGES_DIR}/index.json"
    local current_index
    current_index="$(cat "${index_file}")"

    # Use python if available or pure bash index updater
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json
idx_path, tag, img_id = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(idx_path, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
data[tag] = img_id
with open(idx_path, 'w') as f:
    json.dump(data, f, indent=2)
" "${index_file}" "${tag}" "${image_id}"
    else
        # Append / rewrite simple key in index
        echo "{\"${tag}\": \"${image_id}\"}" > "${index_file}"
    fi

    conduit::log_info "Registered image '${tag}' with ID ${image_id:0:12}"
    echo "${image_id}"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::image_resolve
# Resolves a tag, short ID, or full ID to an image manifest file.
# Arguments:
#   $1 - Identifier (e.g., "alpine:latest", "alpine", "e3b0c442")
# Returns:
#   Full 64-char image ID on stdout
# ------------------------------------------------------------------------------
conduit::image_resolve() {
    local query="$1"
    conduit::image_init

    local index_file="${CONDUIT_IMAGES_DIR}/index.json"

    # 1. Check exact match in tag index
    local matched_id=""
    matched_id="$(conduit::json_get "${query}" "${index_file}" 2>/dev/null || true)"
    if [[ -n "${matched_id}" && "${matched_id}" != "null" ]]; then
        echo "${matched_id}"
        return 0
    fi

    # 2. Check with ":latest" appended if query has no colon
    if [[ "${query}" != *:* ]]; then
        matched_id="$(conduit::json_get "${query}:latest" "${index_file}" 2>/dev/null || true)"
        if [[ -n "${matched_id}" && "${matched_id}" != "null" ]]; then
            echo "${matched_id}"
            return 0
        fi
    fi

    # 3. Check for direct file match by full or partial ID
    local candidate
    for candidate in "${CONDUIT_IMAGES_DIR}"/*.json; do
        [[ ! -f "${candidate}" ]] && continue
        local fname
        fname="$(basename "${candidate}" .json)"
        [[ "${fname}" == "index" ]] && continue

        if [[ "${fname}" == "${query}"* ]]; then
            echo "${fname}"
            return 0
        fi
    done

    conduit::throw "${ERR_IMAGE_NOT_FOUND}" "image '${query}' not found"
    return $?
}

# ------------------------------------------------------------------------------
# conduit::image_inspect
# Returns the full manifest JSON for an image.
# ------------------------------------------------------------------------------
conduit::image_inspect() {
    local query="$1"
    local image_id
    image_id="$(conduit::image_resolve "${query}")" || return 1

    local manifest_file="${CONDUIT_IMAGES_DIR}/${image_id}.json"
    if [[ -f "${manifest_file}" ]]; then
        cat "${manifest_file}"
        return 0
    fi

    conduit::throw "${ERR_IMAGE_NOT_FOUND}" "manifest file missing for image '${image_id}'"
    return $?
}

# ------------------------------------------------------------------------------
# conduit::image_unpack
# Unpacks all layers of an image into destination directory in sequence.
# Arguments:
#   $1 - Image query (tag or ID)
#   $2 - Destination directory
# ------------------------------------------------------------------------------
conduit::image_unpack() {
    local image_query="$1"
    local dest_dir="$2"

    local image_id
    image_id="$(conduit::image_resolve "${image_query}")" || return 1

    local manifest
    manifest="$(conduit::image_inspect "${image_id}")" || return 1

    mkdir -p "${dest_dir}"

    # Extract layers
    # Extract layer digests list
    local digests
    if command -v python3 >/dev/null 2>&1; then
        digests="$(python3 -c "
import sys, json
data = json.loads(sys.argv[1])
for layer in data.get('layers', []):
    print(layer.get('digest', ''))
" "${manifest}")"
    else
        # Single layer extraction fallback
        digests="$(conduit::json_get "layers[0].digest" <<< "${manifest}" 2>/dev/null || true)"
    fi

    local digest
    while IFS= read -r digest; do
        [[ -z "${digest}" ]] && continue
        local clean_hash="${digest#sha256:}"
        local blob_file
        blob_file="$(conduit::cas_path "${clean_hash}")"

        if [[ ! -f "${blob_file}" ]]; then
            conduit::throw "${ERR_LAYER_CORRUPTED}" "layer blob '${clean_hash}' missing from CAS store"
            return $?
        fi

        conduit::log_debug "Unpacking layer '${clean_hash:0:12}'..."
        conduit::layer_extract "${blob_file}" "${dest_dir}" || return 1
        conduit::whiteout_apply "${dest_dir}"
    done <<< "${digests}"

    conduit::log_info "Successfully unpacked image '${image_query}' to '${dest_dir}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::image_list
# Outputs all registered images in space-delimited table format.
# ------------------------------------------------------------------------------
conduit::image_list() {
    conduit::image_init
    local index_file="${CONDUIT_IMAGES_DIR}/index.json"

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json, os

idx_file = sys.argv[1]
img_dir = sys.argv[2]

try:
    with open(idx_file, 'r') as f:
        idx = json.load(f)
except Exception:
    idx = {}

print('REPOSITORY:TAG ID CREATED SIZE')
for tag, img_id in idx.items():
    manifest_path = os.path.join(img_dir, f'{img_id}.json')
    created = 'unknown'
    total_size = 0
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, 'r') as f:
                m = json.load(f)
                created = m.get('created', 'unknown')
                for l in m.get('layers', []):
                    total_size += l.get('size', 0)
        except Exception:
            pass
    print(f'{tag} {img_id[:12]} {created} {total_size}')
" "${index_file}" "${CONDUIT_IMAGES_DIR}"
    fi
}
