#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_004_signal_cleanup_lifo.sh
#
# Bug Description:
#   First-in-first-out cleanup order causes unmount failures when child
#   resources are unmounted after their parent containers are already destroyed.
#
# Regression Fix:
#   conduit::trap_push and conduit::trap_pop enforce strict LIFO execution order.
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "core/signal"

declare -a EXEC_ORDER=()

op_first() {
    EXEC_ORDER+=("first")
}

op_second() {
    EXEC_ORDER+=("second")
}

run_tests() {
    test_plan 2

    conduit::trap_push "op_first"
    conduit::trap_push "op_second"

    # Pop and execute most recent
    conduit::trap_pop
    assert_eq "${EXEC_ORDER[0]}" "second" "trap_pop strictly executes most recently registered task (LIFO)"

    conduit::trap_pop
    assert_eq "${EXEC_ORDER[1]}" "first" "second trap_pop executes first registered task"

    test_summary
}

run_tests
