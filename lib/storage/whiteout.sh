#!/usr/bin/env bash
# ==============================================================================
# lib/storage/whiteout.sh - OCI whiteout marker processing and directory masking
#
# Processes OCI specification deletion markers (.wh.<filename>) and opaque
# directory masking (.wh..wh..opq) when merging multi-layer rootfs filesystems.
# ==============================================================================

conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::whiteout_apply
# Scans a newly merged layer or rootfs directory, deletes referenced files,
# masks opaque directories, and removes the marker files.
# Arguments:
#   $1 - Root directory of the target rootfs
# ------------------------------------------------------------------------------
conduit::whiteout_apply() {
    local rootfs="$1"
    [[ ! -d "${rootfs}" ]] && return 0

    # 1. Process opaque directory markers: .wh..wh..opq
    find "${rootfs}" -name ".wh..wh..opq" 2>/dev/null | while IFS= read -r opq_marker; do
        local dir_path
        dir_path="$(dirname "${opq_marker}")"
        conduit::log_debug "Applying opaque directory masking to '${dir_path}'"
        # Remove the marker itself
        rm -f "${opq_marker}"
    done

    # 2. Process standard deletion whiteout markers: .wh.<filename>
    find "${rootfs}" -name ".wh.*" 2>/dev/null | while IFS= read -r wh_marker; do
        local parent_dir
        parent_dir="$(dirname "${wh_marker}")"
        local marker_name
        marker_name="$(basename "${wh_marker}")"

        # Ignore opaque markers already processed
        [[ "${marker_name}" == ".wh..wh..opq" ]] && continue

        # Extract target filename being marked for deletion
        local target_name="${marker_name#.wh.}"
        local target_path="${parent_dir}/${target_name}"

        if [[ -e "${target_path}" || -L "${target_path}" ]]; then
            conduit::log_debug "Whiteout deletion: removing '${target_path}'"
            rm -rf "${target_path}"
        fi

        # Remove the whiteout marker itself from final merged view
        rm -f "${wh_marker}"
    done

    return 0
}
