#!/usr/bin/env bash
# ==============================================================================
# tests/regression/test_bug_003_dag_self_cycle.sh
#
# Bug Description:
#   Self-referencing dependency cycles (service:service) caused topological
#   schedulers to stall or enter infinite loops.
#
# Regression Fix:
#   Kahn's algorithm detects self-cycles and returns ERR_DAG_CYCLE (70).
# ==============================================================================

_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_TEST_DIR}/../test_helper.sh"

conduit::import "orchestrator/dag"

run_tests() {
    test_plan 2

    local self_loop="serviceA:serviceA"
    assert_false "conduit::dag_toposort '${self_loop}'" "dag_toposort detects self-referencing cycle"

    local multi_cycle="svc1:svc2 svc2:svc3 svc3:svc1"
    assert_false "conduit::dag_toposort '${multi_cycle}'" "dag_toposort detects three-node cycle"

    test_summary
}

run_tests
