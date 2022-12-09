#!/usr/bin/env bash
# ==============================================================================
# tests/test_helper.sh - Assertion library and hermetic test environment fixtures
#
# Provides TAP-compliant test reporting, assertion primitives, and isolated
# sandboxed state directory fixtures for reproducible testing.
# ==============================================================================

# Ensure test runs in isolated temporary state directory
export TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/conduit_test_$$_${RANDOM}}"
export CONDUIT_STATE_DIR="${TEST_TMP_DIR}/state"
export CONDUIT_LOG_LEVEL=4 # Suppress routine logging during tests

# Bootstrap conduit
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONDUIT_ROOT="$(cd "${_DIR}/.." && pwd)"
export CONDUIT_LIB="${CONDUIT_ROOT}/lib"

source "${CONDUIT_LIB}/conduit.sh"
conduit::init_environment

declare -g _TEST_COUNT=0
declare -g _TEST_PASSED=0
declare -g _TEST_FAILED=0

test_plan() {
    local planned="$1"
    echo "1..${planned}"
}

test_ok() {
    local desc="$1"
    (( _TEST_COUNT++ ))
    (( _TEST_PASSED++ ))
    echo "ok ${_TEST_COUNT} - ${desc}"
}

test_fail() {
    local desc="$1"
    local details="${2:-}"
    (( _TEST_COUNT++ ))
    (( _TEST_FAILED++ ))
    echo "not ok ${_TEST_COUNT} - ${desc}"
    if [[ -n "${details}" ]]; then
        echo "#   ${details}"
    fi
}

test_summary() {
    echo "# Total: ${_TEST_COUNT}, Passed: ${_TEST_PASSED}, Failed: ${_TEST_FAILED}"
    if (( _TEST_FAILED > 0 )); then
        return 1
    fi
    return 0
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local desc="${3:-assert_eq}"

    if [[ "${actual}" == "${expected}" ]]; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "expected '${expected}', got '${actual}'"
    fi
}

assert_ne() {
    local actual="$1"
    local unexpected="$2"
    local desc="${3:-assert_ne}"

    if [[ "${actual}" != "${unexpected}" ]]; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "expected not equal to '${unexpected}'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-assert_contains}"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "'${haystack}' does not contain '${needle}'"
    fi
}

assert_true() {
    local cmd="$1"
    local desc="${2:-assert_true: ${cmd}}"

    if eval "${cmd}" >/dev/null 2>&1; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "command failed: ${cmd}"
    fi
}

assert_false() {
    local cmd="$1"
    local desc="${2:-assert_false: ${cmd}}"

    if ! eval "${cmd}" >/dev/null 2>&1; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "command unexpectedly succeeded: ${cmd}"
    fi
}

assert_file_exists() {
    local path="$1"
    local desc="${2:-assert_file_exists: ${path}}"

    if [[ -f "${path}" ]]; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "file not found at '${path}'"
    fi
}

assert_dir_exists() {
    local path="$1"
    local desc="${2:-assert_dir_exists: ${path}}"

    if [[ -d "${path}" ]]; then
        test_ok "${desc}"
    else
        test_fail "${desc}" "directory not found at '${path}'"
    fi
}

cleanup_test_env() {
    if [[ -d "${TEST_TMP_DIR}" && "${TEST_TMP_DIR}" == /tmp/conduit_test_* ]]; then
        rm -rf "${TEST_TMP_DIR}" 2>/dev/null || true
    fi
}
trap cleanup_test_env EXIT INT TERM
