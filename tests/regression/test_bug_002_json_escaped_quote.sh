#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_002_json_escaped_quote.sh
#
# Bug Description:
#   JSON tokenizer misinterprets escaped double quotes (\" within a string)
#   as closing quotes, corrupting subsequent field extractions.
#
# Regression Fix:
#   Python/regex tokenizer safely handles escaped delimiter characters.
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "json/parser"
conduit::import "json/serializer"

run_tests() {
    test_plan 2

    local json_doc='{ "cmd": "echo \"nested quote\" test", "status": "ok" }'

    assert_eq "$(conduit::json_get "cmd" <<< "${json_doc}")" \
        'echo "nested quote" test' \
        "json_get preserves embedded quotes without premature termination"

    assert_eq "$(conduit::json_get "status" <<< "${json_doc}")" \
        "ok" \
        "json_get accurately extracts subsequent field following escaped quote"

    test_summary
}

run_tests
