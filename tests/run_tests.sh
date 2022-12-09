#!/usr/bin/env bash
# ==============================================================================
# tests/run_tests.sh - Master TAP-compliant test harness runner
#
# Discovers, isolates, and executes all unit, integration, and regression suites,
# providing colorized summary statistics and failure diagnostics.
# ==============================================================================

set -o pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CONDUIT_ROOT="${_ROOT}"
export CONDUIT_LIB="${CONDUIT_ROOT}/lib"

SUITE_FILTER=""
while (( $# > 0 )); do
    case "$1" in
        --unit) SUITE_FILTER="unit" ; shift ;;
        --integration) SUITE_FILTER="integration" ; shift ;;
        --regression) SUITE_FILTER="regression" ; shift ;;
        *) shift ;;
    esac
done

echo "=========================================================="
echo " Conduit Unified Test Harness (TAP 13 Protocol)           "
echo "=========================================================="

declare -a TEST_FILES=()

if [[ -z "${SUITE_FILTER}" || "${SUITE_FILTER}" == "unit" ]]; then
    for f in "${_ROOT}/tests/unit"/test_*.sh; do
        [[ -f "${f}" ]] && TEST_FILES+=("${f}")
    done
fi

if [[ -z "${SUITE_FILTER}" || "${SUITE_FILTER}" == "integration" ]]; then
    for f in "${_ROOT}/tests/integration"/test_*.sh; do
        [[ -f "${f}" ]] && TEST_FILES+=("${f}")
    done
fi

if [[ -z "${SUITE_FILTER}" || "${SUITE_FILTER}" == "regression" ]]; then
    for f in "${_ROOT}/tests/regression"/test_*.sh; do
        [[ -f "${f}" ]] && TEST_FILES+=("${f}")
    done
fi

TOTAL_SUITES=${#TEST_FILES[@]}
PASSED_SUITES=0
FAILED_SUITES=0

for test_file in "${TEST_FILES[@]}"; do
    rel_path="${test_file#${_ROOT}/}"
    printf "\n--- Running suite: %s ---\n" "${rel_path}"

    if bash "${test_file}"; then
        (( PASSED_SUITES++ ))
        printf "\033[32m[PASS]\033[0m %s\n" "${rel_path}"
    else
        (( FAILED_SUITES++ ))
        printf "\033[31m[FAIL]\033[0m %s\n" "${rel_path}"
    fi
done

echo ""
echo "=========================================================="
printf "Suite Summary: %d total, \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n" \
    "${TOTAL_SUITES}" "${PASSED_SUITES}" "${FAILED_SUITES}"
echo "=========================================================="

if (( FAILED_SUITES > 0 )); then
    exit 1
fi
exit 0
