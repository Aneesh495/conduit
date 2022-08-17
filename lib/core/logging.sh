#!/usr/bin/env bash
# ==============================================================================
# lib/core/logging.sh - High performance structured logging and terminal styling
#
# Emits contextual log events with severity filtering, ISO-8601 timestamps,
# ANSI terminal color styling, and optional JSON-ND structured streaming.
# ==============================================================================

# Severity thresholds
export LOG_LEVEL_TRACE=0
export LOG_LEVEL_DEBUG=1
export LOG_LEVEL_INFO=2
export LOG_LEVEL_WARN=3
export LOG_LEVEL_ERROR=4
export LOG_LEVEL_FATAL=5

# Active logging configuration
CONDUIT_LOG_LEVEL="${CONDUIT_LOG_LEVEL:-2}"
CONDUIT_LOG_FORMAT="${CONDUIT_LOG_FORMAT:-text}" # 'text' or 'json'
CONDUIT_LOG_FILE="${CONDUIT_LOG_FILE:-}"

# ANSI Terminal Escape Sequences
if [[ -t 2 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    _COLOR_RESET="\033[0m"
    _COLOR_BOLD="\033[1m"
    _COLOR_DIM="\033[2m"
    _COLOR_GRAY="\033[90m"
    _COLOR_RED="\033[31m"
    _COLOR_GREEN="\033[32m"
    _COLOR_YELLOW="\033[33m"
    _COLOR_BLUE="\033[34m"
    _COLOR_MAGENTA="\033[35m"
    _COLOR_CYAN="\033[36m"
else
    _COLOR_RESET=""
    _COLOR_BOLD=""
    _COLOR_DIM=""
    _COLOR_GRAY=""
    _COLOR_RED=""
    _COLOR_GREEN=""
    _COLOR_YELLOW=""
    _COLOR_BLUE=""
    _COLOR_MAGENTA=""
    _COLOR_CYAN=""
fi

conduit::set_log_level() {
    local lvl="$1"
    case "${lvl}" in
        trace|TRACE|0) CONDUIT_LOG_LEVEL=0 ;;
        debug|DEBUG|1) CONDUIT_LOG_LEVEL=1 ;;
        info|INFO|2)   CONDUIT_LOG_LEVEL=2 ;;
        warn|WARN|3)   CONDUIT_LOG_LEVEL=3 ;;
        error|ERROR|4) CONDUIT_LOG_LEVEL=4 ;;
        fatal|FATAL|5) CONDUIT_LOG_LEVEL=5 ;;
        *) echo "conduit: warning: invalid log level '${lvl}', defaulting to INFO" >&2
           CONDUIT_LOG_LEVEL=2 ;;
    esac
}

conduit::_log_emit() {
    local severity_num="$1"
    local severity_str="$2"
    local color="$3"
    local message="$4"
    local caller_func="${FUNCNAME[2]:-main}"

    # Filter out messages below configured threshold
    if (( severity_num < CONDUIT_LOG_LEVEL )); then
        return 0
    fi

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if [[ "${CONDUIT_LOG_FORMAT}" == "json" ]]; then
        # Escaping double quotes in message
        local escaped_msg="${message//\\/\\\\}"
        escaped_msg="${escaped_msg//\"/\\\"}"
        local json_line
        json_line="$(printf '{"timestamp":"%s","level":"%s","caller":"%s","message":"%s"}\n' \
            "${timestamp}" "${severity_str}" "${caller_func}" "${escaped_msg}")"

        echo "${json_line}" >&2
        if [[ -n "${CONDUIT_LOG_FILE}" ]]; then
            echo "${json_line}" >> "${CONDUIT_LOG_FILE}" 2>/dev/null || true
        fi
    else
        local formatted_line
        formatted_line="$(printf "%b[%s]%b %b[%-5s]%b %b[%s]%b %s\n" \
            "${_COLOR_GRAY}" "${timestamp}" "${_COLOR_RESET}" \
            "${color}" "${severity_str}" "${_COLOR_RESET}" \
            "${_COLOR_CYAN}" "${caller_func}" "${_COLOR_RESET}" \
            "${message}")"

        echo -e "${formatted_line}" >&2
        if [[ -n "${CONDUIT_LOG_FILE}" ]]; then
            # Strip ANSI escape codes when writing to persistent log file
            echo -e "${formatted_line}" | sed $'s/\033\\[[0-9;]*m//g' >> "${CONDUIT_LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

conduit::log_trace() {
    conduit::_log_emit "${LOG_LEVEL_TRACE}" "TRACE" "${_COLOR_GRAY}" "$*"
}

conduit::log_debug() {
    conduit::_log_emit "${LOG_LEVEL_DEBUG}" "DEBUG" "${_COLOR_BLUE}" "$*"
}

conduit::log_info() {
    conduit::_log_emit "${LOG_LEVEL_INFO}" "INFO" "${_COLOR_GREEN}" "$*"
}

conduit::log_warn() {
    conduit::_log_emit "${LOG_LEVEL_WARN}" "WARN" "${_COLOR_YELLOW}" "$*"
}

conduit::log_error() {
    conduit::_log_emit "${LOG_LEVEL_ERROR}" "ERROR" "${_COLOR_RED}" "$*"
}

conduit::log_fatal() {
    conduit::_log_emit "${LOG_LEVEL_FATAL}" "FATAL" "${_COLOR_BOLD}${_COLOR_RED}" "$*"
    exit 1
}
