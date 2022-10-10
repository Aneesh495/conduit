#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/rootfs.sh - Synthetic rootfs initialization and device plumbing
#
# Configures container filesystem layout, synthetic devices, network name
# resolution descriptors, and isolated temporary mount hierarchies.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"
conduit::import "core/platform"

# ------------------------------------------------------------------------------
# conduit::rootfs_prepare
# Prepares directory layout, synthetic configuration, and pseudo devices.
# Arguments:
#   $1 - Absolute path to container rootfs directory
#   $2 - Container hostname
#   $3 - (Optional) Container IPv4 address
# ------------------------------------------------------------------------------
conduit::rootfs_prepare() {
    local rootfs="$1"
    local hostname="${2:-conduit}"
    local ip_addr="${3:-127.0.0.1}"

    # Essential filesystem hierarchy
    local d
    for d in bin sbin etc etc/ssl dev proc sys tmp var var/log var/run root usr usr/bin usr/sbin usr/lib; do
        mkdir -p "${rootfs}/${d}"
    done

    # Secure sticky bit on temporary directory
    chmod 1777 "${rootfs}/tmp" 2>/dev/null || true

    # Synthesize /etc/hostname
    echo "${hostname}" > "${rootfs}/etc/hostname"

    # Synthesize /etc/hosts
    cat <<EOF > "${rootfs}/etc/hosts"
127.0.0.1   localhost localhost.localdomain
::1         localhost ip6-localhost ip6-loopback
${ip_addr}  ${hostname}
EOF

    # Synthesize /etc/resolv.conf if not already provided by layer
    if [[ ! -s "${rootfs}/etc/resolv.conf" ]]; then
        cat <<EOF > "${rootfs}/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    fi

    # Device node synthesis
    # On rootless environments or macOS, create symlinks or file stand-ins
    if [[ ! -c "${rootfs}/dev/null" ]]; then
        if [[ "${CONDUIT_IS_ROOT}" == "true" && "${CONDUIT_OS}" == "linux" ]]; then
            mknod -m 666 "${rootfs}/dev/null" c 1 3 2>/dev/null || true
            mknod -m 666 "${rootfs}/dev/zero" c 1 5 2>/dev/null || true
            mknod -m 666 "${rootfs}/dev/random" c 1 8 2>/dev/null || true
            mknod -m 666 "${rootfs}/dev/urandom" c 1 9 2>/dev/null || true
            mknod -m 666 "${rootfs}/dev/tty" c 5 0 2>/dev/null || true
        else
            # Link to host devices for rootless transparent operation
            ln -sf /dev/null "${rootfs}/dev/null" 2>/dev/null || true
            ln -sf /dev/zero "${rootfs}/dev/zero" 2>/dev/null || true
            ln -sf /dev/random "${rootfs}/dev/random" 2>/dev/null || true
            ln -sf /dev/urandom "${rootfs}/dev/urandom" 2>/dev/null || true
            ln -sf /dev/tty "${rootfs}/dev/tty" 2>/dev/null || true
        fi
    fi

    return 0
}
