#!/usr/bin/env bash
# ==============================================================================
# lib/json/parser.sh - Pure Bash JSON tokenizer and path query evaluator
#
# Parses JSON documents and extracts typed values by key path without external
# runtime dependencies, with optional transparent jq/python3 acceleration.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::json_get
# Extracts value at key path from JSON text (file or standard input).
# Usage:
#   conduit::json_get "status" state.json
#   echo '{"name": "conduit"}' | conduit::json_get "name"
# ------------------------------------------------------------------------------
conduit::json_get() {
    local query_path="$1"
    local json_input

    if (( $# >= 2 )); then
        local file_path="$2"
        if [[ ! -f "${file_path}" ]]; then
            return 1
        fi
        json_input="$(cat "${file_path}")"
    else
        json_input="$(cat)"
    fi

    [[ -z "${json_input}" ]] && return 1

    # If python3 or jq is available, use for rapid evaluation
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json

query = sys.argv[1]
raw = sys.stdin.read()
if not raw.strip():
    sys.exit(1)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)

parts = query.split('.')
curr = data
for p in parts:
    if '[' in p and p.endswith(']'):
        k, idx = p[:-1].split('[')
        if k:
            curr = curr[k]
        curr = curr[int(idx)]
    else:
        curr = curr[p]

if isinstance(curr, bool):
    print('true' if curr else 'false')
elif isinstance(curr, (dict, list)):
    print(json.dumps(curr))
else:
    print(curr)
" "${query_path}" <<< "${json_input}" 2>/dev/null && return 0
    fi

    # Pure Bash extraction fallback for key paths
    # Matches simple top-level or dot-notation keys: e.g. "status", "id"
    local target_key="${query_path##*.}"
    local val=""

    # Match string value: "key"\s*:\s*"value"
    if [[ "${json_input}" =~ \"${target_key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Match numeric or boolean value: "key"\s*:\s*([0-9a-zA-Z_-]+)
    if [[ "${json_input}" =~ \"${target_key}\"[[:space:]]*:[[:space:]]*([0-9a-zA-Z_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Match object or array value
    if [[ "${json_input}" =~ \"${target_key}\"[[:space:]]*:[[:space:]]*(\{[^\}]*\}|\[[^\]]*\]) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# ------------------------------------------------------------------------------
# conduit::json_get_array_elements
# Extracts array elements from a given JSON array string.
# ------------------------------------------------------------------------------
conduit::json_get_array_elements() {
    local json_input
    if (( $# >= 1 )); then
        json_input="$1"
    else
        json_input="$(cat)"
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json
raw = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
try:
    arr = json.loads(raw)
    if isinstance(arr, list):
        for item in arr:
            if isinstance(item, (dict, list)):
                print(json.dumps(item))
            else:
                print(item)
except Exception:
    pass
" "${json_input}" 2>/dev/null && return 0
    fi

    # Pure Bash fallback: strip outer brackets and split by commas
    local trimmed="${json_input#\[}"
    trimmed="${trimmed%\]}"
    local IFS=','
    local elem
    for elem in ${trimmed}; do
        # Trim whitespace and quotes
        elem="$(echo "${elem}" | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
        echo "${elem}"
    done
}
