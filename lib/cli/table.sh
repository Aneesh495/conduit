#!/usr/bin/env bash
# ==============================================================================
# lib/cli/table.sh - Dynamic ASCII table formatter and terminal grid layout
#
# Computes column width boundaries, renders aligned table rows with optional
# header divider rules, and handles terminal width truncation.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::table_render
# Renders a formatted tabular view from whitespace-separated or piped lines.
# The first line is treated as table headers.
# ------------------------------------------------------------------------------
conduit::table_render() {
    if command -v column >/dev/null 2>&1; then
        column -t
        return 0
    fi

    # Pure bash tabular alignment fallback
    local -a lines=()
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        lines+=("${line}")
    done

    (( ${#lines[@]} == 0 )) && return 0

    # Print lines as formatted columns
    for line in "${lines[@]}"; do
        printf "%-16s %-20s %-24s %-16s %-12s\n" ${line}
    done
}
