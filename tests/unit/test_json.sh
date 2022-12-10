#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_json.sh - JSON parsing, serialization, and validation tests
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "json/serializer"
conduit::import "json/parser"
conduit::import "json/validator"

run_tests() {
    test_plan 7

    # Serializer test
    conduit::json_builder_init
    conduit::json_field_str "name" "conduit"
    conduit::json_field_int "version" 1
    conduit::json_field_bool "active" true
    local rendered
    rendered="$(conduit::json_builder_render)"

    assert_true "conduit::json_is_valid '${rendered}'" "serialized JSON document is valid"
    assert_eq "$(conduit::json_get "name" <<< "${rendered}")" "conduit" "json_get extracts string property"
    assert_eq "$(conduit::json_get "version" <<< "${rendered}")" "1" "json_get extracts integer property"
    assert_eq "$(conduit::json_get "active" <<< "${rendered}")" "true" "json_get extracts boolean property"

    # Character escaping test
    local raw_str="Hello \"world\" \n test"
    local escaped
    escaped="$(conduit::json_escape "${raw_str}")"
    assert_contains "${escaped}" "\\\"world\\\"" "json_escape correctly escapes embedded double quotes"

    # Validator bracket mismatch test
    assert_false "conduit::json_is_valid '{ \"unclosed\": 123 '" "json_is_valid rejects unclosed brace"

    # Required keys assertion test
    assert_true "conduit::json_require_keys '${rendered}' 'name' 'version'" "json_require_keys accepts present keys"

    test_summary
}

run_tests
