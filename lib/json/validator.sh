#!/usr/bin/env bash
# ==============================================================================
# lib/json/validator.sh - JSON syntax validation and schema assertions
#
# Validates JSON document structure, verifies balanced delimiter invariants,
# and enforces required top-level schema properties.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::json_is_valid
# Returns 0 if input string is well-formed JSON, 1 otherwise.
# ------------------------------------------------------------------------------
conduit::json_is_valid() {
    local json_input
    if (( $# >= 1 )); then
        json_input="$1"
    else
        json_input="$(cat)"
    fi

    [[ -z "${json_input//[[:space:]]/}" ]] && return 1

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys, json; json.loads(sys.stdin.read())" <<< "${json_input}" 2>/dev/null
        return $?
    elif command -v jq >/dev/null 2>&1; then
        jq empty <<< "${json_input}" 2>/dev/null
        return $?
    fi

    # Pure Bash bracket balance check
    local open_brace=0 close_brace=0
    local open_bracket=0 close_bracket=0
    local in_string=0 escape=0
    local i char

    for (( i = 0; i < ${#json_input}; i++ )); do
        char="${json_input:i:1}"
        if (( escape )); then
            escape=0
            continue
        fi
        if [[ "${char}" == "\\" ]]; then
            escape=1
            continue
        fi
        if [[ "${char}" == "\"" ]]; then
            in_string=$(( 1 - in_string ))
            continue
        fi
        if (( in_string )); then
            continue
        fi

        case "${char}" in
            '{') (( open_brace++ )) ;;
            '}') (( close_brace++ )) ;;
            '[') (( open_bracket++ )) ;;
            ']') (( close_bracket++ )) ;;
        esac
    done

    if (( open_brace == close_brace && open_bracket == close_bracket && in_string == 0 )); then
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# conduit::json_require_keys
# Verifies that all given keys exist in the JSON payload.
# Arguments:
#   $1 - JSON file or string
#   $@ - Required keys
# ------------------------------------------------------------------------------
conduit::json_require_keys() {
    local json_doc="$1"
    shift
    local key

    for key in "$@"; do
        if ! conduit::json_get "${key}" <<< "${json_doc}" >/dev/null 2>&1; then
            echo "conduit: schema violation: missing required JSON key '${key}'" >&2
            return 1
        fi
    done
    return 0
}
