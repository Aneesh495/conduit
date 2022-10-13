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
(deny default)

;; Allow basic process lifecycle and execution
(allow process-fork)
(allow process-exec (subpath "${rootfs}"))
(allow process-exec (subpath "/bin"))
(allow process-exec (subpath "/usr/bin"))
(allow process-exec (subpath "/usr/local/bin"))
(allow process-exec (subpath "/opt/homebrew/bin"))

;; Allow read access to container rootfs and dynamic linkers
(allow file-read* (subpath "${rootfs}"))
(allow file-read* (subpath "/usr/lib"))
(allow file-read* (subpath "/System"))
(allow file-read* (subpath "/dev"))
(allow file-read* (subpath "/etc"))

;; Allow writes STRICTLY inside container rootfs
(allow file-write* (subpath "${rootfs}"))

;; Allow reading system sysctl properties
(allow sysctl-read)

;; Pseudo-terminals and tty
(allow file-read* (literal "/dev/tty") (literal "/dev/null") (literal "/dev/zero"))
(allow file-write* (literal "/dev/tty") (literal "/dev/null") (literal "/dev/zero"))

;; Signals within same process group
(allow signal (target same-sandbox))
EOF

    # Configure network access in profile
    if [[ "${net_mode}" == "none" ]]; then
        cat <<EOF >> "${dest_file}"
;; Strict air-gapped network deny
(deny network*)
EOF
    else
        cat <<EOF >> "${dest_file}"
;; Bridge network permissions
(allow network-outbound)
(allow network-inbound (local tcp))
(allow system-socket)
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
