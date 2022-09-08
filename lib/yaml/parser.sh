#!/usr/bin/env bash
# ==============================================================================
# lib/yaml/parser.sh - Pure Bash YAML subset parser for compose manifests
#
# Parses hierarchical YAML documents (mapping objects, scalar keys, lists,
# block literals) into flattened key-value indices and JSON representations.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::yaml_to_json
# Converts a subset YAML document (stdin or file) to canonical JSON format.
# ------------------------------------------------------------------------------
conduit::yaml_to_json() {
    local yaml_input
    if (( $# >= 1 )); then
        local file_path="$1"
        if [[ ! -f "${file_path}" ]]; then
            return 1
        fi
        yaml_input="$(cat "${file_path}")"
    else
        yaml_input="$(cat)"
    fi

    # Acceleration if python3 is available
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, json

lines = sys.stdin.readlines()

def parse_simple_yaml(lines):
    root = {}
    stack = [(0, root)]
    current_list_key = None

    for line in lines:
        raw = line.split('#')[0].rstrip()
        if not raw.strip():
            continue
        indent = len(line) - len(line.lstrip())
        content = raw.strip()

        while stack and indent < stack[-1][0]:
            stack.pop()

        parent = stack[-1][1] if stack else root

        if content.startswith('- '):
            item_val = content[2:].strip().strip('\"\'')
            if current_list_key and isinstance(parent.get(current_list_key), list):
                parent[current_list_key].append(item_val)
            continue

        if ':' in content:
            key, val = content.split(':', 1)
            key = key.strip().strip('\"\'')
            val = val.strip().strip('\"\'')
            if not val:
                # Sub-object or list header
                new_dict = {}
                if isinstance(parent, dict):
                    parent[key] = new_dict
                    stack.append((indent + 2, new_dict))
                    current_list_key = key
            else:
                # Type conversion for booleans and integers
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                elif val.isdigit():
                    val = int(val)
                if isinstance(parent, dict):
                    parent[key] = val
                current_list_key = None

    return root

print(json.dumps(parse_simple_yaml(lines)))
" <<< "${yaml_input}" 2>/dev/null && return 0
    fi

    # Pure Bash basic key-value extractor fallback
    local json="{"
    local first=1
    local line
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}" # strip comments
        line="${line%"${line##*[![:space:]]}"}" # rtrim
        [[ -z "${line}" ]] && continue

        if [[ "${line}" =~ ^[[:space:]]*([a-zA-Z0-9_-]+):[[:space:]]*(.*)$ ]]; then
            local k="${BASH_REMATCH[1]}"
            local v="${BASH_REMATCH[2]}"
            v="${v%\"}"
            v="${v#\"}"
            if [[ -n "${v}" ]]; then
                if (( first == 0 )); then
                    json+=", "
                fi
                first=0
                json+="\"${k}\": \"${v}\""
            fi
        fi
    done <<< "${yaml_input}"
    json+="}"
    echo "${json}"
}

# ------------------------------------------------------------------------------
# conduit::yaml_get
# Queries a property from YAML document using dot notation.
# ------------------------------------------------------------------------------
conduit::yaml_get() {
    local query_path="$1"
    local yaml_file="${2:-}"

    local json_doc
    if [[ -n "${yaml_file}" ]]; then
        json_doc="$(conduit::yaml_to_json "${yaml_file}")" || return 1
    else
        json_doc="$(conduit::yaml_to_json)" || return 1
    fi

    conduit::json_get "${query_path}" <<< "${json_doc}"
}
