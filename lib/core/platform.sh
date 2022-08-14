#!/usr/bin/env bash
# ==============================================================================
# lib/core/platform.sh - Operating system and host kernel capability probes
#
# Detects host virtualization and isolation primitives across Linux and macOS
# Darwin, establishing execution mode (root vs rootless, cgroups v2, sandbox-exec).
# ==============================================================================

# Global platform constants
declare -g CONDUIT_OS="unknown"
declare -g CONDUIT_ARCH="unknown"
declare -g CONDUIT_IS_ROOT="false"
declare -g CONDUIT_HAS_CGROUPS_V2="false"
declare -g CONDUIT_HAS_NAMESPACES="false"
declare -g CONDUIT_HAS_SANDBOX_EXEC="false"
declare -g CONDUIT_HAS_OVERLAYFS="false"
declare -g CONDUIT_HAS_NATIVE_SHIM="false"

conduit::platform_init() {
    # Detect operating system
    case "$(uname -s)" in
        Linux*)  CONDUIT_OS="linux" ;;
        Darwin*) CONDUIT_OS="darwin" ;;
        FreeBSD*) CONDUIT_OS="freebsd" ;;
        *) CONDUIT_OS="unknown" ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)   CONDUIT_ARCH="amd64" ;;
        arm64|aarch64)  CONDUIT_ARCH="arm64" ;;
        armv7l|armhf)   CONDUIT_ARCH="armv7" ;;
        i386|i686)      CONDUIT_ARCH="386" ;;
        *)              CONDUIT_ARCH="$(uname -m)" ;;
    esac

    # Check root privileges
    if (( EUID == 0 )); then
        CONDUIT_IS_ROOT="true"
    else
        CONDUIT_IS_ROOT="false"
    fi

    # Probe Linux specific isolation primitives
    if [[ "${CONDUIT_OS}" == "linux" ]]; then
        # Check cgroups v2
        if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
            CONDUIT_HAS_CGROUPS_V2="true"
        fi

        # Check namespaces via unshare tool or kernel proc
        if command -v unshare >/dev/null 2>&1 && [[ -d /proc/$$/ns ]]; then
            CONDUIT_HAS_NAMESPACES="true"
        fi

        # Check overlayfs in /proc/filesystems
        if grep -q "overlay" /proc/filesystems 2>/dev/null; then
            CONDUIT_HAS_OVERLAYFS="true"
        fi
    fi

    # Probe macOS Darwin specific isolation primitives
    if [[ "${CONDUIT_OS}" == "darwin" ]]; then
        if command -v sandbox-exec >/dev/null 2>&1; then
            CONDUIT_HAS_SANDBOX_EXEC="true"
        fi
    fi

    # Check for compiled native shim binary
    if [[ -x "${CONDUIT_ROOT}/bin/conduit-shim" ]]; then
        CONDUIT_HAS_NATIVE_SHIM="true"
    fi
}

conduit::is_linux() {
    [[ "${CONDUIT_OS}" == "linux" ]]
}

conduit::is_darwin() {
    [[ "${CONDUIT_OS}" == "darwin" ]]
}

conduit::has_native_shim() {
    [[ "${CONDUIT_HAS_NATIVE_SHIM}" == "true" ]]
}

# ------------------------------------------------------------------------------
# conduit::platform_info
# Outputs a diagnostic summary of the host virtualization capability matrix.
# ------------------------------------------------------------------------------
conduit::platform_info() {
    cat <<EOF
Platform Diagnostics:
  OS:                ${CONDUIT_OS}
  Architecture:      ${CONDUIT_ARCH}
  Privilege:         $([ "${CONDUIT_IS_ROOT}" = "true" ] && echo "root (uid 0)" || echo "unprivileged (uid ${EUID})")
  Linux Namespaces:  ${CONDUIT_HAS_NAMESPACES}
  cgroups v2:        ${CONDUIT_HAS_CGROUPS_V2}
  OverlayFS:         ${CONDUIT_HAS_OVERLAYFS}
  Apple Sandbox:     ${CONDUIT_HAS_SANDBOX_EXEC}
  Native Shim:       ${CONDUIT_HAS_NATIVE_SHIM}
EOF
}

# Automatically initialize on module import
conduit::platform_init
