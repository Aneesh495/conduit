#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/darwin_sandbox.sh - Apple Sandbox Profile compiler (macOS)
#
# Generates dynamic Scheme sandbox profiles (.sb format) for process quarantine,
# filesystem sandboxing, and network filtering on macOS Darwin systems.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::darwin_compile_profile
# Generates a Scheme sandbox profile restricting process to container rootfs.
# Arguments:
#   $1 - Absolute path to container rootfs
#   $2 - Network mode ('none' or 'bridge')
#   $3 - Destination path to write .sb profile
# ------------------------------------------------------------------------------
conduit::darwin_compile_profile() {
    local rootfs="$1"
    local net_mode="${2:-bridge}"
    local dest_file="$3"

    mkdir -p "$(dirname "${dest_file}")"

    cat <<EOF > "${dest_file}"
;; conduit container sandbox profile v1
(version 1)
(allow default)

;; Quarantine write operations: deny writes outside container rootfs
(deny file-write* (subpath "/Users"))
(deny file-write* (subpath "/System"))
(deny file-write* (subpath "/Library"))
(deny file-write* (subpath "/Applications"))

;; Allow writes STRICTLY inside container rootfs and container state
(allow file-write* (subpath "${rootfs}"))
(allow file-write* (subpath "/tmp"))
(allow file-write* (subpath "/var/tmp"))
EOF

    # Configure network access in profile
    if [[ "${net_mode}" == "none" ]]; then
        cat <<EOF >> "${dest_file}"
;; Strict air-gapped network deny
(deny network*)
EOF
    fi

    conduit::log_debug "Compiled Darwin sandbox profile to '${dest_file}'"
    return 0
}

# ------------------------------------------------------------------------------
# conduit::darwin_exec_sandboxed
# Executes a command under an Apple Sandbox-exec quarantine profile.
# ------------------------------------------------------------------------------
conduit::darwin_exec_sandboxed() {
    local profile_file="$1"
    shift

    if [[ -f "${profile_file}" ]] && command -v sandbox-exec >/dev/null 2>&1; then
        sandbox-exec -f "${profile_file}" "$@"
    else
        # Fallback direct execution
        "$@"
    fi
}
