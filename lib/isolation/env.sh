#!/usr/bin/env bash
# ==============================================================================
# lib/isolation/env.sh - Hermetic environment scrubbing and variable whitelisting
#
# Cleanses host environment variables, prevents ambient credential leakage,
# and synthesizes deterministic execution environments for isolated processes.
# ==============================================================================

conduit::import "core/types"
conduit::import "core/logging"

# ------------------------------------------------------------------------------
# conduit::env_cleanse
# Generates an isolated array of environment definitions.
# Arguments:
#   $1 - Container hostname
#   $@ - Additional KEY=VALUE pairs specified by user
# Output:
#   Newline-separated KEY=VALUE pairs on stdout
# ------------------------------------------------------------------------------
conduit::env_cleanse() {
    local hostname="${1:-conduit}"
    shift || true

    # Default baseline hermetic environment
    local -a safe_env=(
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        "HOSTNAME=${hostname}"
        "HOME=/root"
        "USER=root"
        "TERM=xterm-256color"
        "CONDUIT_CONTAINER=1"
        "SHLVL=1"
        "PWD=/"
    )

    local pair
    for pair in "${safe_env[@]}"; do
        echo "${pair}"
    done

    # Append user-provided environment overrides
    while (( $# > 0 )); do
        local user_var="$1"
        shift
        if [[ "${user_var}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
            echo "${user_var}"
        fi
    done
}

# ------------------------------------------------------------------------------
# conduit::env_export_args
# Formats environment variables into "env" command invocation arguments.
# ------------------------------------------------------------------------------
conduit::env_export_args() {
    local env_stream
    env_stream="$(conduit::env_cleanse "$@")"

    local -a args=("-i") # Start with empty environment
    local line
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        args+=("${line}")
    done <<< "${env_stream}"

    printf "%s\n" "${args[@]}"
}
