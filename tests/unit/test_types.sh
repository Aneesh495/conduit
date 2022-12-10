#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_types.sh - Unit tests for type predicates and resource parsers
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "core/types"

test_plan 10

# Test 1: Integer predicates
assert_true "conduit::is_int 42" "is_int positive integer"
assert_true "conduit::is_int -100" "is_int negative integer"
assert_false "conduit::is_int 3.14" "is_int rejects float"
assert_false "conduit::is_int abc" "is_int rejects string"

# Test 2: Byte size parsing
assert_eq "$(conduit::parse_bytes 1024)" "1024" "parse_bytes raw integer"
assert_eq "$(conduit::parse_bytes 512k)" "524288" "parse_bytes 512k"
assert_eq "$(conduit::parse_bytes 2g)" "2147483648" "parse_bytes 2g"

# Test 3: Port binding parser
read -r hip hport cport proto < <(conduit::parse_port_binding "8080:80/tcp")
assert_eq "${hip}" "0.0.0.0" "port binding default host ip"
assert_eq "${hport}" "8080" "port binding host port"
assert_eq "${cport}" "80" "port binding container port"

test_summary
