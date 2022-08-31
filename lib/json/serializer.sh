#!/usr/bin/env bash
# ==============================================================================
# lib/json/serializer.sh - Type-aware JSON object and array builder
#
# Provides deterministic serialization of structured metadata, container state,
# OCI manifests, and SLSA provenance trees with character escaping.
# ==============================================================================

# ------------------------------------------------------------------------------
# conduit::json_escape
# Escapes backslashes, double quotes, newlines, tabs, and control characters.
# ------------------------------------------------------------------------------
conduit::json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf "%s" "${str}"
}

# ------------------------------------------------------------------------------
# In-memory JSON Object Builder
# ------------------------------------------------------------------------------

conduit::json_builder_init() {
    declare -g _CONDUIT_JSON_BUFFER=""
    declare -g _CONDUIT_JSON_FIRST_KEY=1
}

conduit::json_field_str() {
    local key="$1"
    local val="$2"
    local esc_key esc_val
    esc_key="$(conduit::json_escape "${key}")"
    esc_val="$(conduit::json_escape "${val}")"

    if (( _CONDUIT_JSON_FIRST_KEY == 0 )); then
        _CONDUIT_JSON_BUFFER+=", "
    fi
    _CONDUIT_JSON_FIRST_KEY=0
    _CONDUIT_JSON_BUFFER+="\"${esc_key}\": \"${esc_val}\""
}

conduit::json_field_int() {
    local key="$1"
    local val="$2"
    local esc_key
    esc_key="$(conduit::json_escape "${key}")"

    if (( _CONDUIT_JSON_FIRST_KEY == 0 )); then
        _CONDUIT_JSON_BUFFER+=", "
    fi
    _CONDUIT_JSON_FIRST_KEY=0
    _CONDUIT_JSON_BUFFER+="\"${esc_key}\": ${val}"
}

conduit::json_field_bool() {
    local key="$1"
    local val="$2"
    local esc_key
    esc_key="$(conduit::json_escape "${key}")"
    local b="false"
    [[ "${val}" == "true" || "${val}" == "1" ]] && b="true"

    if (( _CONDUIT_JSON_FIRST_KEY == 0 )); then
        _CONDUIT_JSON_BUFFER+=", "
    fi
    _CONDUIT_JSON_FIRST_KEY=0
    _CONDUIT_JSON_BUFFER+="\"${esc_key}\": ${b}"
}

conduit::json_field_raw() {
    local key="$1"
    local raw_json="$2"
    local esc_key
    esc_key="$(conduit::json_escape "${key}")"

    if (( _CONDUIT_JSON_FIRST_KEY == 0 )); then
        _CONDUIT_JSON_BUFFER+=", "
    fi
    _CONDUIT_JSON_FIRST_KEY=0
    _CONDUIT_JSON_BUFFER+="\"${esc_key}\": ${raw_json}"
}

conduit::json_builder_render() {
    printf "{ %s }\n" "${_CONDUIT_JSON_BUFFER}"
}

# ------------------------------------------------------------------------------
# conduit::json_array_from_list
# Converts whitespace or line-separated list of strings into JSON array.
# ------------------------------------------------------------------------------
conduit::json_array_from_list() {
    local first=1
    printf "["
    local item
    for item in "$@"; do
        if (( first == 0 )); then
            printf ", "
        fi
        first=0
        local esc
        esc="$(conduit::json_escape "${item}")"
        printf "\"%s\"" "${esc}"
    done
    printf "]"
}
