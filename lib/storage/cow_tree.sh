#!/usr/bin/env bash
# ==============================================================================
# lib/storage/cow_tree.sh - Userspace Copy-on-Write (CoW) shadow tree engine
#
# Provides deterministic copy-on-write filesystem virtualization using hardlink
# shadow trees and inode modification journals, enabling instant container
# instantiation without root privileges across Linux and macOS Darwin.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "core/platform"
conduit::import "storage/whiteout"

# ------------------------------------------------------------------------------
# conduit::cow_init_tree
# Synthesizes an isolated container rootfs from a base image tree using hardlinks.
# Arguments:
#   $1 - Base image root directory (immutable lower layer)
#   $2 - Target container rootfs directory
#   $3 - Container state directory (to store journals)
# ------------------------------------------------------------------------------
conduit::cow_init_tree() {
    local base_dir="$1"
    local target_rootfs="$2"
    local state_dir="$3"

    if [[ ! -d "${base_dir}" ]]; then
        conduit::throw "${ERR_FILE_NOT_FOUND}" "base image directory not found '${base_dir}'"
        return $?
    fi

    mkdir -p "${target_rootfs}"
    mkdir -p "${state_dir}"

    local journal="${state_dir}/cow_journal.log"
    echo "# conduit CoW journal v1 - initialized $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${journal}"

    conduit::log_debug "Synthesizing hardlink shadow tree: '${base_dir}' -> '${target_rootfs}'"

    # Fast hardlink replication
    if conduit::is_linux; then
        cp -al "${base_dir}/." "${target_rootfs}/" 2>/dev/null || {
            # Fallback recursive copy if hardlink copy across mount points fails
            cp -a "${base_dir}/." "${target_rootfs}/"
        }
    else
        # macOS Darwin hardlink traversal
        (
            cd "${base_dir}" || exit 1
            find . -mindepth 1 | while IFS= read -r rel_path; do
                local clean="${rel_path#./}"
                local src_item="${base_dir}/${clean}"
                local dst_item="${target_rootfs}/${clean}"

                if [[ -d "${src_item}" ]]; then
                    mkdir -p "${dst_item}"
                elif [[ -L "${src_item}" ]]; then
                    # Replicate symlink
                    local target
                    target="$(readlink "${src_item}")"
                    ln -s "${target}" "${dst_item}" 2>/dev/null || true
                elif [[ -f "${src_item}" ]]; then
                    # Create hardlink to conserve disk and enable CoW
                    ln "${src_item}" "${dst_item}" 2>/dev/null || cp -p "${src_item}" "${dst_item}"
                fi
            done
        )
    fi

    # Apply any whiteout markers that might exist in base
    conduit::whiteout_apply "${target_rootfs}"

    return 0
}

# ------------------------------------------------------------------------------
# conduit::cow_break_link
# Breaks hardlink for target path to prepare for safe mutation (Copy-on-Write).
# Arguments:
#   $1 - Target file path within container rootfs
#   $2 - Journal file path
# ------------------------------------------------------------------------------
conduit::cow_break_link() {
    local file_path="$1"
    local journal="${2:-}"

    [[ ! -f "${file_path}" ]] && return 0

    # Query link count
    local nlink=1
    if conduit::is_darwin; then
        nlink="$(stat -f "%l" "${file_path}" 2>/dev/null || echo "1")"
    else
        nlink="$(stat -c "%h" "${file_path}" 2>/dev/null || echo "1")"
    fi

    # If file has multiple links, it points to base layer inode; perform CoW
    if (( nlink > 1 )); then
        local tmp_copy="${file_path}.cow.$$.${RANDOM}"
        cp -p "${file_path}" "${tmp_copy}" || return 1
        rm -f "${file_path}" || return 1
        mv -f "${tmp_copy}" "${file_path}" || return 1

        if [[ -n "${journal}" ]]; then
            mkdir -p "$(dirname "${journal}")"
            echo "COW_BREAK ${file_path} $(date +%s)" >> "${journal}"
        fi
        conduit::log_trace "CoW broken hardlink for '${file_path}'"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# conduit::cow_snapshot
# Takes a persistent snapshot of modified inodes in the container rootfs.
# ------------------------------------------------------------------------------
conduit::cow_snapshot() {
    local target_rootfs="$1"
    local snapshot_dest="$2"

    mkdir -p "${snapshot_dest}"
    cp -a "${target_rootfs}/." "${snapshot_dest}/"
}
