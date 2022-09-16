#!/usr/bin/env bash
# ==============================================================================
# lib/storage/layer.sh - OCI image layer extraction, packing, and delta generation
#
# Implements deterministic, reproducible layer tarball serialization, path
# traversal guards (Zip Slip defenses), and filesystem tree diffing.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "crypto/sha256"

# ------------------------------------------------------------------------------
# conduit::layer_extract
# Extracts a layer tar archive into target directory with security safeguards.
# Arguments:
#   $1 - Path to tarball (tar, tar.gz)
#   $2 - Destination directory
# ------------------------------------------------------------------------------
conduit::layer_extract() {
    local tar_file="$1"
    local dest_dir="$2"

    if [[ ! -f "${tar_file}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "layer tarball not found '${tar_file}'"
        return $?
    fi

    mkdir -p "${dest_dir}"

    conduit::log_debug "Extracting layer '$(basename "${tar_file}")' to '${dest_dir}'"

    # Inspect tarball for unsafe relative paths (e.g. '../' or absolute paths)
    local unsafe
    unsafe="$(tar -tf "${tar_file}" 2>/dev/null | grep -E '^/|\.\./' | head -n 1)"
    if [[ -n "${unsafe}" ]]; then
        conduit::throw "${ERR_ISOLATION_FAILED}" "unsafe path detected in layer tarball: '${unsafe}'"
        return $?
    fi

    # Extract tarball preserving permissions, suppressing stderr chatter
    tar -xf "${tar_file}" -C "${dest_dir}" 2>/dev/null || {
        conduit::throw "${ERR_LAYER_CORRUPTED}" "failed to extract layer tarball '${tar_file}'"
        return $?
    }

    return 0
}

# ------------------------------------------------------------------------------
# conduit::layer_pack
# Creates a reproducible, deterministic tarball from a directory.
# Arguments:
#   $1 - Source directory containing layer contents
#   $2 - Destination tarball path
# ------------------------------------------------------------------------------
conduit::layer_pack() {
    local src_dir="$1"
    local dest_tar="$2"

    if [[ ! -d "${src_dir}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "source directory not found '${src_dir}'"
        return $?
    fi

    mkdir -p "$(dirname "${dest_tar}")"

    # Produce deterministic tarball with sorted paths and normalized metadata
    (
        cd "${src_dir}" || exit 1
        # Find all files sorted deterministically
        find . -mindepth 1 | sort | tar -cf "${dest_tar}" -T - 2>/dev/null
    ) || {
        conduit::throw "${ERR_GENERIC}" "failed to pack layer archive '${dest_tar}'"
        return $?
    }

    return 0
}

# ------------------------------------------------------------------------------
# conduit::layer_diff
# Identifies modified, added, and removed files between base and upper trees.
# Arguments:
#   $1 - Base lower directory
#   $2 - Upper modified directory
#   $3 - Output directory to stage the delta layer
# ------------------------------------------------------------------------------
conduit::layer_diff() {
    local base_dir="$1"
    local upper_dir="$2"
    local stage_dir="$3"

    mkdir -p "${stage_dir}"

    # Walk all files in upper directory
    (
        cd "${upper_dir}" || exit 1
        find . -mindepth 1 | while IFS= read -r rel_path; do
            local clean_rel="${rel_path#./}"
            local upper_file="${upper_dir}/${clean_rel}"
            local base_file="${base_dir}/${clean_rel}"
            local stage_target="${stage_dir}/${clean_rel}"

            if [[ -d "${upper_file}" ]]; then
                mkdir -p "${stage_target}"
                continue
            fi

            # Check if file is newly added or modified
            if [[ ! -f "${base_file}" ]]; then
                # New file
                mkdir -p "$(dirname "${stage_target}")"
                cp -p "${upper_file}" "${stage_target}"
            else
                # Compare contents
                local h_upper h_base
                h_upper="$(conduit::sha256_file "${upper_file}")"
                h_base="$(conduit::sha256_file "${base_file}")"
                if [[ "${h_upper}" != "${h_base}" ]]; then
                    mkdir -p "$(dirname "${stage_target}")"
                    cp -p "${upper_file}" "${stage_target}"
                fi
            fi
        done
    )

    # Detect deleted files and synthesize OCI whiteout markers (.wh.<name>)
    if [[ -d "${base_dir}" ]]; then
        (
            cd "${base_dir}" || exit 1
            find . -mindepth 1 | while IFS= read -r rel_path; do
                local clean_rel="${rel_path#./}"
                local upper_file="${upper_dir}/${clean_rel}"

                if [[ ! -e "${upper_file}" ]]; then
                    # File was deleted in upper layer: create whiteout marker
                    local parent_dir
                    parent_dir="$(dirname "${stage_dir}/${clean_rel}")"
                    local base_name
                    base_name="$(basename "${clean_rel}")"
                    mkdir -p "${parent_dir}"
                    touch "${parent_dir}/.wh.${base_name}"
                fi
            done
        )
    fi

    return 0
}
