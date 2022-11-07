#!/usr/bin/env bash
# ==============================================================================
# lib/supervisor/pty.sh - Interactive pseudo-terminal allocation and raw mode
#
# Connects interactive terminal sessions (-i -t) using the native conduit-shim
# accelerator or POSIX stty raw multiplexing with guaranteed terminal restoration.
# ==============================================================================

conduit::import "core/logging"
conduit::import "core/platform"

# ------------------------------------------------------------------------------
# conduit::pty_run
# Executes target command wrapped inside an interactive PTY session.
# ------------------------------------------------------------------------------
conduit::pty_run() {
    local -a cmd=("$@")

    # If native shim is available and stdin is a terminal, use conduit-shim pty
    if conduit::has_native_shim && [[ -t 0 ]]; then
        exec "${CONDUIT_ROOT}/bin/conduit-shim" pty "${cmd[@]}"
    fi

    # Fallback POSIX terminal setup
    if [[ -t 0 ]]; then
        local saved_stty
        saved_stty="$(stty -g 2>/dev/null || true)"
        # Trap to restore terminal settings on exit
        trap '[[ -n "${saved_stty}" ]] && stty "${saved_stty}" 2>/dev/null || stty sane 2>/dev/null || true' EXIT INT TERM
        stty raw -echo 2>/dev/null || true
        "${cmd[@]}"
        local ret=$?
        [[ -n "${saved_stty}" ]] && stty "${saved_stty}" 2>/dev/null || stty sane 2>/dev/null || true
        return "${ret}"
    else
        "${cmd[@]}"
        return $?
    fi
}
