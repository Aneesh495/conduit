#!/usr/bin/env bash
# ==============================================================================
# lib/cli/progress.sh - Terminal progress bars and activity spinners
#
# Emits real-time visual progress feedback, percentage indicators, and spinners
# with terminal capability detection and non-interactive silence modes.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::progress_bar
# Renders a progress bar on stderr.
# Arguments:
#   $1 - Current progress count
#   $2 - Total progress count
#   $3 - (Optional) Label message
# ------------------------------------------------------------------------------
conduit::progress_bar() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"

    [[ ! -t 2 ]] && return 0 # Suppress in non-terminal mode

    local width=30
    local percent=$(( current * 100 / total ))
    local completed=$(( current * width / total ))
    local remaining=$(( width - completed ))

    local bar=""
    local i
    for (( i = 0; i < completed; i++ )); do bar+="#"; done
    for (( i = 0; i < remaining; i++ )); do bar+="-"; done

    printf "\r\033[36m%s\033[0m [%s] %3d%% (%d/%d)" "${label}" "${bar}" "${percent}" "${current}" "${total}" >&2
    if (( current == total )); then
        printf "\n" >&2
    fi
}
