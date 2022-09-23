#!/usr/bin/env bash
# ==============================================================================
# lib/storage/overlay.sh - Native Linux OverlayFS driver integration
#
# Provides kernel-level union mount acceleration when running with elevated
# capabilities on modern Linux systems, with automatic fallback to userspace CoW.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/errors"
conduit::import "core/logging"
conduit::import "core/platform"

# ------------------------------------------------------------------------------
# conduit::overlay_is_supported
# Probes whether kernel overlayfs can be mounted.
# ------------------------------------------------------------------------------
conduit::overlay_is_supported() {
    conduit::is_linux || return 1
    [[ "${CONDUIT_IS_ROOT}" == "true" ]] || return 1
    grep -q "overlay" /proc/filesystems 2>/dev/null || return 1
    return 0
}

# ------------------------------------------------------------------------------
# conduit::overlay_mount
# Mounts lowerdir, upperdir, and workdir into merged destination using overlayfs.
# ------------------------------------------------------------------------------
conduit::overlay_mount() {
    local lower_dir="$1"
    local upper_dir="$2"
    local work_dir="$3"
    local merged_dir="$4"

    if ! conduit::overlay_is_supported; then
        conduit::throw "${ERR_COW_FAILURE}" "overlayfs not supported or insufficient privileges"
        return $?
    fi

    mkdir -p "${upper_dir}" "${work_dir}" "${merged_dir}"

    local opts="lowerdir=${lower_dir},upperdir=${upper_dir},workdir=${work_dir}"
    mount -t overlay overlay -o "${opts}" "${merged_dir}" 2>/dev/null || {
        conduit::throw "${ERR_COW_FAILURE}" "failed to mount overlayfs to '${merged_dir}'"
        return $?
    }

    conduit::log_debug "Mounted kernel overlayfs onto '${merged_dir}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::overlay_unmount
# Unmounts merged overlayfs directory safely.
# ------------------------------------------------------------------------------
conduit::overlay_unmount() {
    local merged_dir="$1"
    [[ ! -d "${merged_dir}" ]] && return 0

    if mountpoint -q "${merged_dir}" 2>/dev/null; then
        umount "${merged_dir}" 2>/dev/null || umount -l "${merged_dir}" 2>/dev/null || true
    fi
}
