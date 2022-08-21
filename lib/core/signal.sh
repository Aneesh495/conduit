#!/usr/bin/env bash
# ==============================================================================
# lib/core/signal.sh - Safe signal dispatch, LIFO cleanup stack, and process traps
#
# Manages signal propagation (INT, TERM, HUP, QUIT, EXIT) ensuring resource
# deallocation, FIFO removal, and child process group termination without leaks.
# ==============================================================================

# Array holding cleanup callbacks to run on process termination (executed LIFO)
declare -g -a _CONDUIT_CLEANUP_STACK=()
declare -g _CONDUIT_TRAPS_INSTALLED=0

# ------------------------------------------------------------------------------
# conduit::trap_push
# Pushes a shell command or function call onto the cleanup stack.
# ------------------------------------------------------------------------------
conduit::trap_push() {
    local cmd="$1"
    [[ -z "${cmd}" ]] && return 0
    _CONDUIT_CLEANUP_STACK+=("${cmd}")
    if (( _CONDUIT_TRAPS_INSTALLED == 0 )); then
        conduit::trap_install
    fi
}

# ------------------------------------------------------------------------------
# conduit::trap_pop
# Removes and executes the most recent cleanup command from the stack.
# ------------------------------------------------------------------------------
conduit::trap_pop() {
    local count="${#_CONDUIT_CLEANUP_STACK[@]}"
    if (( count == 0 )); then
        return 0
    fi
    local last_idx=$(( count - 1 ))
    local cmd="${_CONDUIT_CLEANUP_STACK[last_idx]}"
    unset "_CONDUIT_CLEANUP_STACK[last_idx]"
    eval "${cmd}" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# conduit::trap_discard
# Removes the most recent cleanup command without executing it (e.g. on success).
# ------------------------------------------------------------------------------
conduit::trap_discard() {
    local count="${#_CONDUIT_CLEANUP_STACK[@]}"
    if (( count == 0 )); then
        return 0
    fi
    local last_idx=$(( count - 1 ))
    unset "_CONDUIT_CLEANUP_STACK[last_idx]"
}

# ------------------------------------------------------------------------------
# conduit::_trap_handler
# Internal signal handler executing all registered cleanup callbacks in LIFO order.
# ------------------------------------------------------------------------------
conduit::_trap_handler() {
    local sig="$1"
    local exit_code="$2"

    # Temporarily ignore signals during cleanup execution to avoid recursion
    trap '' EXIT INT TERM HUP QUIT

    local count="${#_CONDUIT_CLEANUP_STACK[@]}"
    local i
    for (( i = count - 1; i >= 0; i-- )); do
        local cmd="${_CONDUIT_CLEANUP_STACK[i]}"
        eval "${cmd}" 2>/dev/null || true
    done
    _CONDUIT_CLEANUP_STACK=()

    if [[ "${sig}" != "EXIT" ]]; then
        # Re-raise signal to ensure standard process exit semantics
        trap - "${sig}"
        kill -s "${sig}" $$ 2>/dev/null || exit "${exit_code}"
    else
        exit "${exit_code}"
    fi
}

# ------------------------------------------------------------------------------
# conduit::trap_install
# Installs signal hooks for EXIT, INT, TERM, HUP, QUIT.
# ------------------------------------------------------------------------------
conduit::trap_install() {
    if (( _CONDUIT_TRAPS_INSTALLED == 1 )); then
        return 0
    fi

    trap 'conduit::_trap_handler EXIT $?' EXIT
    trap 'conduit::_trap_handler INT 130' INT
    trap 'conduit::_trap_handler TERM 143' TERM
    trap 'conduit::_trap_handler HUP 129' HUP
    trap 'conduit::_trap_handler QUIT 131' QUIT

    _CONDUIT_TRAPS_INSTALLED=1
}
